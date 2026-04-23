// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";
import {MessageHashUtils} from "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

import {ERC165Checker} from "./libs/ERC165Checker.sol";
import {LibSecp256k1} from "./libs/LibSecp256k1.sol";
import {LibSchnorr} from "./libs/LibSchnorr.sol";
import {LibMuSig2KeyAgg} from "./libs/LibMuSig2KeyAgg.sol";
import {INodeRegistry} from "./interfaces/INodeRegistry.sol";
import {IFeed} from "./interfaces/IFeed.sol";
import {IFeedStructs} from "./interfaces/IFeedStructs.sol";
import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";

/// @title NodeRegistry
/// @notice Registry for managing nodes and verifying Schnorr signatures
/// @dev Uses SSTORE2 for efficient storage of node public keys, supports up to 256 nodes
contract NodeRegistry is INodeRegistry, ERC165, Initializable {
    using MessageHashUtils for bytes32;
    using ERC165Checker for address;
    using LibSchnorr for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.JacobianPoint;

    /// @notice Maximum number of allowed signers that can be stored in the signer set.
    /// with SSTORE2 we can store up to 382 signers, but we limit to 256 to use bitmaps
    uint256 constant MAX_NODES = 256;

    /// @notice Index from which valid signer entries start.
    /// @dev We use 1-based indexing, so index 0 is reserved and unused.
    ///      This helps avoid confusion with default zero values.
    uint256 constant START_INDEX = 1;

    /// @notice mapping of signer addresses to their indexes in the signers array
    mapping(address node => uint256 index) public nodeIndexes;

    /// @notice pointer to signers array stored with SSTORE2, signers[0] is empty cause we use 1-based indexing
    address public pointer;

    /// @notice Per-job state packed into one 32-byte slot.
    ///         Layout: [high 224 bits = seed] [low 32 bits = round]
    ///         Seed is the 256-bit keccak output with its low 32 bits zeroed (224 bits of entropy
    ///         is more than sufficient). A zero slot means the job has not been initialized.
    ///         Use getJobSeed() / getJobRound() for unpacked reads.
    mapping(bytes32 jobId => bytes32) public jobState;

    /// @dev Bitmask for the round portion of a packed jobState slot (low 32 bits).
    uint256 private constant ROUND_MASK = type(uint32).max;

    /// @dev Byte offset in `abi.encode(LibSecp256k1.Point[])` where point words start
    ///      (32-byte head offset + 32-byte array length).
    uint256 private constant EFFECTIVE_KEYS_ARRAY_HEAD = 64;

    /// @dev `abi.encode(PubkeysBlob)` layout (Solidity ABI): 128-byte head (offset to keys + `muSigXAgg`
    ///      x|y), then `keys` as length word + 64·L coordinate words. User payload = `code.length - 1`
    ///      = 160 + 64·L bytes for `keys.length == L`.
    uint256 private constant PUBKEYS_ABI_HEAD_BYTES = 128;
    uint256 private constant PUBKEYS_KEYS_LEN_WORD = 32;

    /// @notice Cumulative publish participation count per 1-based registry node index (aligns with effective key index).
    mapping(uint256 nodeIndex => uint256) public participationCounts;

    /// @notice Redundancy buffer added to signaturesRequired for selection group size
    uint256 public redundancyBuffer;

    IAccessControlManager public _accessControlManager;

    /// @notice SSTORE2 pointer to abi.encode(LibSecp256k1.Point[] effectiveKeys) only.
    ///         Kept separate from `pointer` so publish() reads the smallest possible blob.
    address public effectiveKeysPointer;

    /// @notice SSTORE2 blob: raw signer keys (index 0 unused) and MuSig2 aggregate key.
    ///         effectiveKeys are stored separately under effectiveKeysPointer.
    struct PubkeysBlob {
        LibSecp256k1.Point[] keys;
        LibSecp256k1.Point muSigXAgg;
    }

    modifier onlyProtocolAdmin() {
        _accessControlManager.verifyProtocolAdmin(msg.sender);
        _;
    }

    function initialize(address accessControlManager) external override initializer {
        _accessControlManager = IAccessControlManager(accessControlManager);
        _accessControlManager.verifyProtocolAdmin(msg.sender);

        redundancyBuffer = 2;

        LibSecp256k1.Point[] memory emptyArray = new LibSecp256k1.Point[](1);
        pointer = SSTORE2.write(abi.encode(PubkeysBlob({keys: emptyArray, muSigXAgg: LibSecp256k1.ZERO_POINT()})));
        effectiveKeysPointer = SSTORE2.write(abi.encode(emptyArray));
    }

    /// @inheritdoc INodeRegistry
    function initializeJob(bytes32 jobId) external override onlyProtocolAdmin {
        if (jobState[jobId] != bytes32(0)) revert("Already initialized");

        bytes32 initialSeed = keccak256(abi.encodePacked(jobId, block.chainid, block.timestamp));
        // round = 0 packed in low 32 bits; seed truncated to 224 bits in high bits
        bytes32 packedInitial = _packJobState(initialSeed, 0);
        jobState[jobId] = packedInitial;

        emit LogJobInitialized(jobId, _unpackSeed(packedInitial));
    }

    /// @inheritdoc INodeRegistry
    function getJobRound(bytes32 jobId) external view override returns (uint32 round) {
        (, round) = _readJobState(jobId);
    }

    /// @inheritdoc INodeRegistry
    function getJobSeed(bytes32 jobId) external view override returns (bytes32 seed) {
        (seed,) = _readJobState(jobId);
    }

    /// @inheritdoc INodeRegistry
    function getGroupSize(uint256 signaturesRequired) external view override returns (uint256 groupSize) {
        groupSize = signaturesRequired + redundancyBuffer;
    }

    function publish(DataUpdate calldata dataUpdate, SchnorrSignature calldata schnorrData) external {
        address feed = dataUpdate.feed;
        require(feed != address(0), "Zero address");

        (, uint256 minSignaturesThreshold, bytes32 jobId,) = IFeed(feed).getFeedConfig();
        require(jobId == dataUpdate.jobId, "Invalid feed");

        (bytes32 prevSeed, uint32 prevRound) = _readJobState(jobId);
        require(uint256(dataUpdate.round) == uint256(prevRound) + 1, "Invalid round");

        uint256 _nodeCount = _nodeCountFromPointer(pointer);
        require(_nodeCount > 0, "No nodes");

        _verifySignature(
            _constructMessage(dataUpdate), schnorrData, minSignaturesThreshold, dataUpdate.round, prevSeed, _nodeCount
        );

        bytes32 newSeed = _commitParticipationAndJobRound(jobId, prevSeed, dataUpdate, schnorrData);

        IFeed(feed).publish(IFeedStructs.Answer({value: dataUpdate.value, timestamp: dataUpdate.timestamp}));

        emit LogAnswerPublished(
            feed, dataUpdate.value, dataUpdate.timestamp, schnorrData.signersBitmap, dataUpdate.round, newSeed
        );
    }

    /// @inheritdoc INodeRegistry
    function verifySignature(
        bytes32 message,
        SchnorrSignature calldata schnorrData,
        uint256 minSignaturesThreshold,
        uint32 round,
        bytes32 seed,
        uint256 nCount
    ) external view {
        _verifySignature(message, schnorrData, minSignaturesThreshold, round, seed, nCount);
    }

    /// @inheritdoc INodeRegistry
    function addNode(bytes memory compressedPubKey) external onlyProtocolAdmin {
        LibSecp256k1.Point memory pubkey = LibSecp256k1.decompress(compressedPubKey);
        if (pubkey.isZeroPoint()) revert("Invalid public key");
        if (pubkey.toAddress() == address(0)) revert("Zero address");

        PubkeysBlob memory blob = abi.decode(SSTORE2.read(pointer), (PubkeysBlob));
        uint256 nextIndex = blob.keys.length;
        if (nextIndex - START_INDEX >= MAX_NODES) revert("Max nodes reached");

        address node = pubkey.toAddress();

        if (nodeIndexes[node] != 0) revert("Node already added");

        LibSecp256k1.Point[] memory newKeys = new LibSecp256k1.Point[](nextIndex + 1);
        for (uint256 i; i < blob.keys.length; ++i) {
            newKeys[i] = blob.keys[i];
        }
        newKeys[blob.keys.length] = pubkey;
        blob.keys = newKeys;

        LibSecp256k1.Point[] memory newEffectiveKeys;
        (newEffectiveKeys, blob.muSigXAgg) = LibMuSig2KeyAgg.computeEffectiveKeysAndAggregate(blob.keys);

        address newPointer = SSTORE2.write(abi.encode(blob));
        pointer = newPointer;
        effectiveKeysPointer = SSTORE2.write(abi.encode(newEffectiveKeys));

        nodeIndexes[node] = nextIndex;
        participationCounts[nextIndex] = 1; // to avoid cold sstore in publish()

        emit LogNodeAdded(node, nextIndex, newPointer);
    }

    function removeNode(address node) external onlyProtocolAdmin {
        uint256 index = nodeIndexes[node];
        if (index == 0) revert("Not node");

        PubkeysBlob memory blob = abi.decode(SSTORE2.read(pointer), (PubkeysBlob));
        uint256 len = blob.keys.length;
        if (index >= len) revert("Bad index");

        if (index != len - 1) {
            blob.keys[index] = blob.keys[len - 1];
            nodeIndexes[blob.keys[index].toAddress()] = index;
        }

        LibSecp256k1.Point[] memory shorter = new LibSecp256k1.Point[](len - 1);
        for (uint256 i; i < len - 1; ++i) {
            shorter[i] = blob.keys[i];
        }
        blob.keys = shorter;

        LibSecp256k1.Point[] memory newEffectiveKeys;
        (newEffectiveKeys, blob.muSigXAgg) = LibMuSig2KeyAgg.computeEffectiveKeysAndAggregate(blob.keys);

        address newPointer = SSTORE2.write(abi.encode(blob));
        pointer = newPointer;
        effectiveKeysPointer = SSTORE2.write(abi.encode(newEffectiveKeys));
        delete nodeIndexes[node];

        emit LogNodeRemoved(node, index, newPointer);
    }

    function isNode(address node) external view returns (bool isActive) {
        isActive = nodeIndexes[node] != 0;
    }

    /// @inheritdoc INodeRegistry
    function getTotalNodes() external view override returns (uint256 totalSigners) {
        totalSigners = _nodeCountFromPointer(pointer);
    }

    function getNodesSetHash() external view override returns (bytes32 hash) {
        hash = keccak256(SSTORE2.read(pointer));
    }

    /// @inheritdoc INodeRegistry
    function getMuSigAggregateKey() external view override returns (uint256 x, uint256 y) {
        PubkeysBlob memory blob = abi.decode(SSTORE2.read(pointer), (PubkeysBlob));
        x = blob.muSigXAgg.x;
        y = blob.muSigXAgg.y;
    }

    /// @inheritdoc INodeRegistry
    function getNodeIndex(address node) external view returns (uint256 index) {
        index = nodeIndexes[node];
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(INodeRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @dev Active node count from SSTORE2 `pointer` runtime size (no stored `nodeCount` slot).
    ///      Matches `keys.length - 1` for `PubkeysBlob` written by this contract.
    function _nodeCountFromPointer(address ptr) private view returns (uint256 n) {
        uint256 len = ptr.code.length;
        // SSTORE2: 1-byte STOP prefix + abi.encode(PubkeysBlob). Minimum L=1 (placeholder only) → payload 224.
        unchecked {
            uint256 payload = len - 1;
            if (payload < PUBKEYS_ABI_HEAD_BYTES + PUBKEYS_KEYS_LEN_WORD + 64) revert("Bad pubkey blob");
            uint256 coordBytes = payload - PUBKEYS_ABI_HEAD_BYTES - PUBKEYS_KEYS_LEN_WORD;
            if (coordBytes % 64 != 0) revert("Bad pubkey blob");
            uint256 keysLen = coordBytes / 64;
            if (keysLen < START_INDEX) revert("Bad pubkey blob");
            if (keysLen > MAX_NODES + START_INDEX) revert("Bad pubkey blob");
            n = keysLen - START_INDEX;
        }
    }

    function _readJobState(bytes32 jobId) internal view returns (bytes32 seed, uint32 round) {
        bytes32 packed = jobState[jobId];
        if (packed == bytes32(0)) revert("Job not initialized");
        seed = _unpackSeed(packed);
        round = _unpackRound(packed);
    }

    /// @dev Pack a seed + round into one bytes32 slot.
    ///      Seed is truncated to 224 bits (low 32 bits zeroed); round occupies the low 32 bits.
    function _packJobState(bytes32 seed, uint32 round) private pure returns (bytes32) {
        return bytes32((uint256(seed) & ~ROUND_MASK) | uint256(round));
    }

    /// @dev Extract the 224-bit seed from a packed jobState slot (low 32 bits are always 0).
    function _unpackSeed(bytes32 packed) private pure returns (bytes32) {
        return bytes32(uint256(packed) & ~ROUND_MASK);
    }

    /// @dev Extract the 32-bit round counter from a packed jobState slot.
    function _unpackRound(bytes32 packed) private pure returns (uint32) {
        return uint32(uint256(packed));
    }

    /// @dev Updates participation counters + hash, advances job seed/round; returns new seed.
    function _commitParticipationAndJobRound(
        bytes32 jobId,
        bytes32 prevSeed,
        DataUpdate calldata dataUpdate,
        SchnorrSignature calldata schnorrData
    ) internal returns (bytes32 newSeed) {
        uint256 sb = uint256(schnorrData.signersBitmap);
        uint256 pos;
        while (sb != 0) {
            pos = _ctz256(sb);
            unchecked {
                ++participationCounts[pos + 1];
            }
            sb ^= uint256(1) << pos;
        }

        bytes32 rawSeed = keccak256(abi.encodePacked(prevSeed, dataUpdate.value, dataUpdate.timestamp));
        bytes32 packedJob = _packJobState(rawSeed, dataUpdate.round);
        jobState[jobId] = packedJob;
        newSeed = _unpackSeed(packedJob);
    }

    function _deriveBitmap(bytes32 seed, uint32 round, uint256 nCount, uint256 groupSize)
        internal
        pure
        returns (uint256 bitmap)
    {
        if (groupSize > nCount) revert("groupSize exceeds nodeCount");
        uint256 selected;
        uint256 attempt;
        while (selected < groupSize) {
            uint256 pos = uint256(keccak256(abi.encodePacked(seed, uint256(round), attempt))) % nCount;
            uint256 bit = uint256(1) << pos;
            if (bitmap & bit == 0) {
                bitmap |= bit;
                selected++;
            }
            unchecked {
                ++attempt;
            }
        }
    }

    /// @dev Hamming weight for 256 bits (parallel SWAR).
    function _popCount(uint256 x) private pure returns (uint256 c) {
        unchecked {
            x -= (x >> 1) & 0x5555555555555555555555555555555555555555555555555555555555555555;
            x = (x & 0x3333333333333333333333333333333333333333333333333333333333333333)
                + ((x >> 2) & 0x3333333333333333333333333333333333333333333333333333333333333333);
            x = (x + (x >> 4)) & 0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f;
            // 16-byte horizontal add per 128-bit lane (max sum 16 * 8 = 128)
            uint256 rep16 = 0x01010101010101010101010101010101;
            uint256 lo = x & ((uint256(1) << 128) - 1);
            uint256 hi = x >> 128;
            c = ((lo * rep16) >> 120) + ((hi * rep16) >> 120);
        }
    }

    /// @dev Trailing zero count (index of lowest set bit). `x` must be nonzero.
    function _ctz256(uint256 x) private pure returns (uint256 r) {
        unchecked {
            if ((x & type(uint128).max) == 0) {
                r += 128;
                x >>= 128;
            }
            if ((x & type(uint64).max) == 0) {
                r += 64;
                x >>= 64;
            }
            if ((x & type(uint32).max) == 0) {
                r += 32;
                x >>= 32;
            }
            if ((x & type(uint16).max) == 0) {
                r += 16;
                x >>= 16;
            }
            if ((x & type(uint8).max) == 0) {
                r += 8;
                x >>= 8;
            }
            if ((x & 0xf) == 0) {
                r += 4;
                x >>= 4;
            }
            if ((x & 0x3) == 0) {
                r += 2;
                x >>= 2;
            }
            if ((x & 0x1) == 0) {
                ++r;
            }
        }
    }

    /// @dev Reads one effective public key (x, y) from the SSTORE2 blob written as
    ///      `abi.encode(LibSecp256k1.Point[])`, using a 64-byte slice only (no full decode).
    function _readEffectiveKeyXY(address ptr, uint256 idx) private view returns (uint256 x, uint256 y) {
        bytes memory chunk =
            SSTORE2.read(ptr, EFFECTIVE_KEYS_ARRAY_HEAD + idx * 64, EFFECTIVE_KEYS_ARRAY_HEAD + (idx + 1) * 64);
        assembly ("memory-safe") {
            x := mload(add(chunk, 0x20))
            y := mload(add(chunk, 0x40))
        }
    }

    /// @dev Verifies a Schnorr signature against the MuSig2 aggregate of the declared
    ///      signing coalition. Reads effectiveKeysPointer (the smaller, split blob) rather
    ///      than the full PubkeysBlob.
    function _verifySignature(
        bytes32 message,
        SchnorrSignature calldata schnorrData,
        uint256 minSignaturesThreshold,
        uint32 round,
        bytes32 seed,
        uint256 _nodeCount
    ) internal view {
        if (schnorrData.signature == bytes32(0)) revert("Invalid signature");
        if (schnorrData.commitment == address(0)) revert("Invalid commitment");

        uint256 sb = uint256(schnorrData.signersBitmap);
        if (sb == 0) revert("Invalid signers bitmap");

        // Bits may only be set for 1-based indices 1.._nodeCount (0-based positions 0.._nodeCount-1).
        uint256 validMask = _nodeCount >= 256 ? type(uint256).max : (uint256(1) << _nodeCount) - 1;
        if (sb & ~validMask != 0) revert("Invalid signers bitmap");

        uint256 numberSigners = _popCount(sb);
        if (numberSigners < minSignaturesThreshold) revert("Not enough signatures");

        uint256 grpSize = minSignaturesThreshold + redundancyBuffer;
        uint256 bm = _deriveBitmap(seed, round, _nodeCount, grpSize);

        address keysPtr = effectiveKeysPointer;

        // Ascending 1-based index order: peel lowest set bit from `rem` each iteration.
        bool aggInit;
        uint256 ax;
        uint256 ay;
        uint256 az;
        uint256 rem = sb;
        while (rem != 0) {
            uint256 bit;
            uint256 pos;
            unchecked {
                bit = rem & (~rem + 1);
                pos = _ctz256(bit);
                rem ^= bit;
            }
            if (bm & bit == 0) revert("Signer not selected");

            uint256 signerIndex = pos + 1;
            (uint256 epx, uint256 epy) = _readEffectiveKeyXY(keysPtr, signerIndex);
            if (!aggInit) {
                (ax, ay, az) = (epx, epy, 1);
                aggInit = true;
            } else {
                (ax, ay, az) = LibSecp256k1.addAffinePointToXYZ(ax, ay, az, epx, epy);
            }
        }

        LibSecp256k1.Point memory aggPubKey = LibSecp256k1.toAffineModexpXYZ(ax, ay, az);

        bool isValid = aggPubKey.verifySignatureTrusted(message, schnorrData.signature, schnorrData.commitment);
        if (!isValid) revert("Invalid signature");
    }

    function _constructMessage(DataUpdate calldata dataUpdate) internal pure returns (bytes32 message) {
        message = keccak256(abi.encodePacked(dataUpdate.jobId, dataUpdate.value, dataUpdate.timestamp))
            .toEthSignedMessageHash();
    }
}
