// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";
import {MessageHashUtils} from "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

import {ERC165Checker} from "./libs/ERC165Checker.sol";
import {LibSecp256k1} from "./libs/LibSecp256k1.sol";
import {LibSchnorr} from "./libs/LibSchnorr.sol";
import {INodeRegistry} from "./interfaces/INodeRegistry.sol";
import {IFeed} from "./interfaces/IFeed.sol";
import {IFeedStructs} from "./interfaces/IFeedStructs.sol";
import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {PubkeyBlobLib} from "./libs/PubkeyBlobLib.sol";
import {BitmapLib} from "./libs/BitmapLib.sol";

/// @title NodeRegistry
/// @notice Registry for managing nodes and verifying Schnorr signatures
/// @dev Uses SSTORE2 for efficient storage of node public keys, supports up to 256 nodes
contract NodeRegistry is INodeRegistry, ERC165, Initializable {
    using MessageHashUtils for bytes32;
    using ERC165Checker for address;
    using LibSchnorr for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.JacobianPoint;
    using PubkeyBlobLib for bytes;
    using BitmapLib for uint256;

    uint256 constant MAX_NODES = 256;
    uint256 constant START_INDEX = 1;

    bytes32 private constant POP_DOMAIN = keccak256("MOLPHA_NODE_REGISTRATION_V1");

    mapping(address node => uint256 index) public nodeIndexes;
    mapping(bytes32 jobId => bytes32) public jobState;
    mapping(uint256 nodeIndex => uint256) public participationCounts;

    /// @notice Pointer to `abi.encode(LibSecp256k1.Point[])` raw keys with index 0 placeholder.
    address public rawKeysPointer;
    uint256 public nodeCount;

    /// @notice Per-index coordinates for O(1) removal aggregate update.
    mapping(uint256 index => uint256 x) public nodeKeyX;
    mapping(uint256 index => uint256 y) public nodeKeyY;

    uint256 public redundancyBuffer;

    IAccessControlManager public _accessControlManager;

    uint256 private constant ROUND_MASK = type(uint32).max;
    uint256 private constant KEYS_ARRAY_HEAD = 64;
    uint256 private constant SSTORE2_DATA_OFFSET = 1;
    uint256 private constant POINT_COORD_BYTES = 64;

    struct BitmapValidation {
        uint256 bitmap;
        uint256 signerCount;
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
        emptyArray[0] = LibSecp256k1.ZERO_POINT();
        rawKeysPointer = SSTORE2.write(abi.encode(emptyArray));
    }

    /// @inheritdoc INodeRegistry
    function initializeJob(bytes32 jobId, uint64 startTime) external override onlyProtocolAdmin {
        if (jobState[jobId] != bytes32(0)) revert("Already initialized");

        bytes32 initialSeed = keccak256(abi.encodePacked(jobId, uint256(0), startTime));
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
        require(dataUpdate.round == prevRound + 1, "Invalid round");

        uint256 _nodeCount = nodeCount;
        require(_nodeCount > 0, "No nodes");

        _verifySignature(
            _constructMessage(dataUpdate),
            schnorrData,
            minSignaturesThreshold,
            dataUpdate.round,
            prevSeed,
            _nodeCount,
            true
        );

        bytes32 newSeed = _advanceJobRound(jobId, prevSeed, dataUpdate);

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
    ) external {
        _verifySignature(message, schnorrData, minSignaturesThreshold, round, seed, nCount, false);
    }

    /// @inheritdoc INodeRegistry
    function addNode(bytes memory compressedPubKey, bytes memory popSignature) external onlyProtocolAdmin {
        LibSecp256k1.Point memory pubkey = LibSecp256k1.decompress(compressedPubKey);
        if (pubkey.isZeroPoint()) revert("Invalid public key");
        if (pubkey.toAddress() == address(0)) revert("Zero address");
        _verifyPop(pubkey, compressedPubKey, popSignature);

        bytes memory keysBlob = SSTORE2.read(rawKeysPointer);
        uint256 nextIndex = keysBlob.getNodesLength();
        if (nextIndex - START_INDEX >= MAX_NODES) revert("Max nodes reached");

        address node = pubkey.toAddress();

        if (nodeIndexes[node] != 0) revert("Node already added");

        LibSecp256k1.Point memory agg;
        if (nextIndex == START_INDEX) {
            agg = pubkey;
        } else {
            LibSecp256k1.Point memory currAgg = keysBlob.getNode(0);
            (uint256 ax, uint256 ay, uint256 az) =
                LibSecp256k1.addAffinePointToXYZ(currAgg.x, currAgg.y, 1, pubkey.x, pubkey.y);
            agg = LibSecp256k1.toAffineModexpXYZ(ax, ay, az);
        }

        keysBlob.addPubkeyWithAggregate(pubkey, agg);
        address newPointer = SSTORE2.write(keysBlob);
        rawKeysPointer = newPointer;

        nodeIndexes[node] = nextIndex;
        nodeKeyX[nextIndex] = pubkey.x;
        nodeKeyY[nextIndex] = pubkey.y;
        participationCounts[nextIndex] = 1; // to avoid cold sstore in publish()
        unchecked {
            ++nodeCount;
        }

        emit LogNodeAdded(node, nextIndex, newPointer);
    }

    function removeNode(address node) external onlyProtocolAdmin {
        uint256 index = nodeIndexes[node];
        if (index == 0) revert("Not node");

        bytes memory keysBlob = SSTORE2.read(rawKeysPointer);
        uint256 len = keysBlob.getNodesLength();
        if (index >= len) revert("Bad index");

        uint256 px = nodeKeyX[index];
        uint256 py = nodeKeyY[index];
        LibSecp256k1.Point memory nextAgg;
        if (len == START_INDEX + 1) {
            nextAgg = LibSecp256k1.ZERO_POINT();
        } else {
            uint256 negY = LibSecp256k1.fieldP() - py;
            LibSecp256k1.Point memory currAgg = keysBlob.getNode(0);
            (uint256 ax, uint256 ay, uint256 az) =
                LibSecp256k1.addAffinePointToXYZ(currAgg.x, currAgg.y, 1, px, negY);
            nextAgg = LibSecp256k1.toAffineModexpXYZ(ax, ay, az);
        }

        if (index != len - 1) {
            LibSecp256k1.Point memory swappedNode = keysBlob.getNode(len - 1);
            keysBlob.setNode(index, swappedNode);
            nodeIndexes[swappedNode.toAddress()] = index;
            nodeKeyX[index] = swappedNode.x;
            nodeKeyY[index] = swappedNode.y;
        }

        keysBlob.removePubkeyWithAggregate(index, nextAgg);
        address newPointer = SSTORE2.write(keysBlob);
        rawKeysPointer = newPointer;
        delete nodeKeyX[len - 1];
        delete nodeKeyY[len - 1];
        delete nodeIndexes[node];
        unchecked {
            --nodeCount;
        }

        emit LogNodeRemoved(node, index, newPointer);
    }

    function isNode(address node) external view returns (bool isActive) {
        isActive = nodeIndexes[node] != 0;
    }

    /// @inheritdoc INodeRegistry
    function getTotalNodes() external view override returns (uint256 totalSigners) {
        totalSigners = nodeCount;
    }

    function getNodesSetHash() external view override returns (bytes32 hash) {
        hash = keccak256(SSTORE2.read(rawKeysPointer));
    }

    /// @inheritdoc INodeRegistry
    function getAggregateKey() external view override returns (uint256 x, uint256 y) {
        bytes memory keysBlob = SSTORE2.read(rawKeysPointer);
        LibSecp256k1.Point memory aggregate = keysBlob.getNode(0);
        x = aggregate.x;
        y = aggregate.y;
    }

    /// @inheritdoc INodeRegistry
    function getNodeIndex(address node) external view returns (uint256 index) {
        index = nodeIndexes[node];
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(INodeRegistry).interfaceId || super.supportsInterface(interfaceId);
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

    /// @dev Updates packed job seed/round after a successful publish (participation is applied in `_verifySignature`).
    function _advanceJobRound(bytes32 jobId, bytes32 prevSeed, DataUpdate calldata dataUpdate)
        internal
        returns (bytes32 newSeed)
    {
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

    /// @dev Copies one affine key (64 bytes) from the SSTORE2 `abi.encode(LibSecp256k1.Point[])` blob into
    ///      `out64` (must be `new bytes(64)` from the caller) to avoid per-signer `bytes` allocation.
    function _readNodeKeyXYInto(address ptr, uint256 idx, bytes memory out64) private view {
        uint256 codeStart = SSTORE2_DATA_OFFSET + KEYS_ARRAY_HEAD + idx * 64;
        assembly ("memory-safe") {
            extcodecopy(ptr, add(out64, 32), codeStart, 64)
        }
    }

    /// @dev Verifies a Schnorr signature against the plain-sum aggregate of the declared
    ///      signing coalition. Reads signer keys directly from `rawKeysPointer` blob.
    /// @param recordParticipation If true (publish path), increment `participationCounts` for each signer bit in the same loop as key aggregation.
    function _verifySignature(
        bytes32 message,
        SchnorrSignature calldata schnorrData,
        uint256 minSignaturesThreshold,
        uint32 round,
        bytes32 seed,
        uint256 _nodeCount,
        bool recordParticipation
    ) internal {
        if (schnorrData.signature == bytes32(0)) revert("Invalid signature");
        if (schnorrData.commitment == address(0)) revert("Invalid commitment");

        BitmapValidation memory validation = _validateSignersBitmap(schnorrData.signersBitmap, _nodeCount);
        if (validation.signerCount < minSignaturesThreshold) revert("Not enough signatures");

        uint256 grpSize = minSignaturesThreshold + redundancyBuffer;
        uint256 bm = _deriveBitmap(seed, round, _nodeCount, grpSize);

        address keysPtr = rawKeysPointer;
        bytes memory keyScratch = new bytes(64);

        // Ascending 1-based index order: peel lowest set bit from `rem` each iteration.
        bool aggInit;
        uint256 ax;
        uint256 ay;
        uint256 az;
        uint256 rem = validation.bitmap;
        while (rem != 0) {
            uint256 bit;
            uint256 pos;
            unchecked {
                bit = rem & (~rem + 1);
                pos = bit.ctz256();
                rem ^= bit;
            }
            if (bm & bit == 0) revert("Signer not selected");

            uint256 signerIndex = pos + 1;
            _readNodeKeyXYInto(keysPtr, signerIndex, keyScratch);
            uint256 epx;
            uint256 epy;
            assembly ("memory-safe") {
                epx := mload(add(keyScratch, 32))
                epy := mload(add(keyScratch, 64))
            }
            if (recordParticipation) {
                unchecked {
                    ++participationCounts[signerIndex];
                }
            }
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

    /// @dev Ensures signer bitmap is non-empty, within node bounds and returns signer count.
    function _validateSignersBitmap(bytes32 signersBitmap, uint256 _nodeCount)
        private
        pure
        returns (BitmapValidation memory result)
    {
        uint256 sb = uint256(signersBitmap);
        if (sb == 0) revert("Invalid signers bitmap");

        // Bits may only be set for 1-based indices 1.._nodeCount (0-based positions 0.._nodeCount-1).
        uint256 validMask = _nodeCount >= 256 ? type(uint256).max : (uint256(1) << _nodeCount) - 1;
        if (sb & ~validMask != 0) revert("Invalid signers bitmap");

        result.bitmap = sb;
        result.signerCount = sb.popCount();
    }

    function _constructMessage(DataUpdate calldata dataUpdate) internal pure returns (bytes32 message) {
        message = keccak256(abi.encodePacked(dataUpdate.jobId, dataUpdate.value, dataUpdate.timestamp, dataUpdate.round))
            .toEthSignedMessageHash();
    }

    function _verifyPop(LibSecp256k1.Point memory pubkey, bytes memory compressedPubKey, bytes memory popSignature)
        private
        view
    {
        bytes32 digest = keccak256(abi.encodePacked(POP_DOMAIN, address(this), compressedPubKey)).toEthSignedMessageHash();
        address signer = _recoverEcdsa(digest, popSignature);
        if (signer == address(0) || signer != pubkey.toAddress()) revert("Invalid PoP");
    }

    function _recoverEcdsa(bytes32 digest, bytes memory sig) private pure returns (address signer) {
        if (sig.length != 65) revert("Invalid PoP");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly ("memory-safe") {
            r := mload(add(sig, 0x20))
            s := mload(add(sig, 0x40))
            v := byte(0, mload(add(sig, 0x60)))
        }
        if (v < 27) {
            v += 27;
        }
        if (v != 27 && v != 28) revert("Invalid PoP");
        signer = ecrecover(digest, v, r, s);
    }
}
