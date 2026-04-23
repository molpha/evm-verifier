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
    /// @notice Per-job round state stored via SSTORE2 (seed + last completed round).
    struct JobState {
        bytes32 seed;
        uint32 round;
    }

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

    /// @notice SSTORE2 pointer per jobId for abi.encode(JobState)
    mapping(bytes32 jobId => address) public jobStatePointers;

    /// @notice keccak256(abi.encode(uint32[] participation counts per 1-based node index))
    bytes32 public participationMapHash;

    /// @notice Redundancy buffer added to signaturesRequired for selection group size
    uint256 public redundancyBuffer;

    IAccessControlManager public _accessControlManager;

    /// @notice SSTORE2 blob: signer list (index 0 unused) plus full-set MuSig2 aggregate key
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
        participationMapHash = _zeroParticipationMapHash(0);

        LibSecp256k1.Point[] memory emptyArray = new LibSecp256k1.Point[](1);
        pointer = SSTORE2.write(
            abi.encode(
                PubkeysBlob({
                    keys: emptyArray,
                    muSigXAgg: LibSecp256k1.ZERO_POINT()
                })
            )
        );
    }

    /// @inheritdoc INodeRegistry
    function initializeJob(bytes32 jobId) external override onlyProtocolAdmin {
        if (jobStatePointers[jobId] != address(0)) revert("Already initialized");

        bytes32 initialSeed = keccak256(abi.encodePacked(jobId, block.chainid, block.timestamp));
        address p = SSTORE2.write(abi.encode(JobState({seed: initialSeed, round: 0})));
        jobStatePointers[jobId] = p;

        emit LogJobInitialized(jobId, initialSeed);
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

    function publish(
        DataUpdate calldata dataUpdate,
        SchnorrSignature calldata schnorrData,
        uint32[] calldata participationMap
    ) external {
        address feed = dataUpdate.feed;
        require(feed != address(0), "Zero address");

        bytes32 jobId = IFeed(feed).getJobId();
        require(jobId == dataUpdate.jobId, "Invalid feed");

        (bytes32 prevSeed, uint32 prevRound) = _readJobState(jobId);
        require(uint256(dataUpdate.round) == uint256(prevRound) + 1, "Invalid round");

        require(
            keccak256(abi.encode(participationMap)) == participationMapHash,
            "Invalid participation map"
        );

        uint256 minSignaturesThreshold = IFeed(feed).getMinSignaturesThreshold();

        uint256 nodeCount = _getNodeCount();
        require(nodeCount > 0, "No nodes");
        require(participationMap.length == nodeCount, "Bad participation length");

        _verifySignature(
            _constructMessage(dataUpdate),
            schnorrData,
            minSignaturesThreshold,
            dataUpdate.round,
            prevSeed,
            nodeCount
        );

        bytes32 newSeed = _commitParticipationAndJobRound(
            jobId,
            prevSeed,
            dataUpdate,
            participationMap,
            schnorrData
        );

        IFeed(feed).publish(
            IFeedStructs.Answer({value: dataUpdate.value, timestamp: dataUpdate.timestamp})
        );

        emit LogAnswerPublished(
            feed,
            dataUpdate.value,
            dataUpdate.timestamp,
            schnorrData.signers,
            dataUpdate.round,
            newSeed
        );
    }

    /// @inheritdoc INodeRegistry
    function verifySignature(
        bytes32 message,
        SchnorrSignature calldata schnorrData,
        uint256 minSignaturesThreshold,
        uint32 round,
        bytes32 seed,
        uint256 nodeCount
    ) external view {
        _verifySignature(message, schnorrData, minSignaturesThreshold, round, seed, nodeCount);
    }

    /// @inheritdoc INodeRegistry
    function addNode(bytes memory compressedPubKey) external onlyProtocolAdmin {
        LibSecp256k1.Point memory pubkey = LibSecp256k1.decompress(compressedPubKey);
        if (pubkey.isZeroPoint()) revert("Invalid public key");
        if (pubkey.toAddress() == address(0)) revert("Zero address");

        PubkeysBlob memory blob = abi.decode(SSTORE2.read(pointer), (PubkeysBlob));
        uint256 nextIndex = blob.keys.length;
        if (blob.keys.length - START_INDEX >= MAX_NODES) revert("Max nodes reached");

        address node = pubkey.toAddress();

        if (nodeIndexes[node] != 0) revert("Node already added");

        LibSecp256k1.Point[] memory newKeys = new LibSecp256k1.Point[](nextIndex + 1);
        for (uint256 i; i < blob.keys.length; ++i) {
            newKeys[i] = blob.keys[i];
        }
        newKeys[blob.keys.length] = pubkey;
        blob.keys = newKeys;
        blob.muSigXAgg = LibMuSig2KeyAgg.aggregateRegistryKeys(blob.keys);

        address newPointer = SSTORE2.write(abi.encode(blob));
        pointer = newPointer;

        nodeIndexes[node] = nextIndex;

        participationMapHash = _zeroParticipationMapHash(blob.keys.length - START_INDEX);

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
        blob.muSigXAgg = LibMuSig2KeyAgg.aggregateRegistryKeys(blob.keys);

        address newPointer = SSTORE2.write(abi.encode(blob));
        pointer = newPointer;
        delete nodeIndexes[node];

        participationMapHash = _zeroParticipationMapHash(blob.keys.length - START_INDEX);

        emit LogNodeRemoved(node, index, newPointer);
    }

    function isNode(address node) external view returns (bool isActive) {
        isActive = nodeIndexes[node] != 0;
    }

    /// @inheritdoc INodeRegistry
    function getTotalNodes()
        external
        view
        override
        returns (uint256 totalSigners)
    {
        totalSigners = _getNodeCount();
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

    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(INodeRegistry).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function _readJobState(bytes32 jobId) internal view returns (bytes32 seed, uint32 round) {
        address p = jobStatePointers[jobId];
        if (p == address(0)) revert("Job not initialized");
        JobState memory js = abi.decode(SSTORE2.read(p), (JobState));
        return (js.seed, js.round);
    }

    /// @dev Updates participation counters + hash, advances job seed/round; returns new seed.
    function _commitParticipationAndJobRound(
        bytes32 jobId,
        bytes32 prevSeed,
        DataUpdate calldata dataUpdate,
        uint32[] calldata participationMap,
        SchnorrSignature calldata schnorrData
    ) internal returns (bytes32 newSeed) {
        uint32[] memory updatedMap = new uint32[](participationMap.length);
        uint256 len = participationMap.length;
        for (uint256 i; i < len; ++i) {
            updatedMap[i] = participationMap[i];
        }
        uint256 nSign = schnorrData.signers.length;
        for (uint256 i; i < nSign; ++i) {
            uint256 idx = schnorrData.signers[i];
            if (idx == 0 || idx > len) revert("Invalid signer index");
            updatedMap[idx - 1]++;
        }

        participationMapHash = keccak256(abi.encode(updatedMap));
        emit LogParticipationUpdated(participationMapHash, updatedMap);

        newSeed = keccak256(abi.encodePacked(prevSeed, dataUpdate.value, dataUpdate.timestamp));
        jobStatePointers[jobId] = SSTORE2.write(
            abi.encode(JobState({seed: newSeed, round: dataUpdate.round}))
        );
    }

    function _deriveBitmap(
        bytes32 seed,
        uint32 round,
        uint256 nodeCount,
        uint256 groupSize
    ) internal pure returns (uint256 bitmap) {
        if (groupSize > nodeCount) revert("groupSize exceeds nodeCount");
        uint256 selected;
        uint256 attempt;
        while (selected < groupSize) {
            uint256 pos = uint256(keccak256(abi.encodePacked(seed, uint256(round), attempt)))
                % nodeCount;
            uint256 bit = uint256(1) << pos;
            if (bitmap & bit == 0) {
                bitmap |= bit;
                selected++;
            }
            attempt++;
        }
    }

    /// @dev Used by publish(): single pass over signers combines selection bitmap check +
    ///      aggregate pubkey accumulation. Signers not in the round bitmap are rejected;
    ///      selected nodes that did NOT sign are simply not in the list (redundancyBuffer allows this).
    function _verifySignature(
        bytes32 message,
        SchnorrSignature calldata schnorrData,
        uint256 minSignaturesThreshold,
        uint32 round,
        bytes32 seed,
        uint256 nodeCount
    ) internal view {
        if (schnorrData.signature == bytes32(0)) revert("Invalid signature");
        if (schnorrData.signers.length == 0) revert("Invalid signers order");
        if (schnorrData.commitment == address(0)) revert("Invalid commitment");

        uint256 numberSigners = schnorrData.signers.length;
        if (numberSigners < minSignaturesThreshold) revert("Not enough signatures");

        uint256 grpSize = minSignaturesThreshold + redundancyBuffer;
        uint256 bm = _deriveBitmap(seed, round, nodeCount, grpSize);

        LibSecp256k1.Point[] memory pubKeys = _getPubKeys();
        uint256 signerSetLength = pubKeys.length; // nodeCount + 1 (index 0 is placeholder)

        uint256 firstIndex = schnorrData.signers[0];
        if (firstIndex == 0 || firstIndex >= signerSetLength) revert("Invalid index");
        if (bm & (uint256(1) << (firstIndex - 1)) == 0) revert("Signer not selected");

        LibSecp256k1.Point[] memory signerPts = new LibSecp256k1.Point[](numberSigners);
        signerPts[0] = pubKeys[firstIndex];
        for (uint256 i = START_INDEX; i < numberSigners; i++) {
            uint256 signerIndex = schnorrData.signers[i];

            if (signerIndex == 0 || signerIndex >= signerSetLength) revert("Invalid index");
            if (signerIndex <= schnorrData.signers[i - 1]) revert("Invalid signers order");
            if (bm & (uint256(1) << (signerIndex - 1)) == 0) revert("Signer not selected");

            signerPts[i] = pubKeys[signerIndex];
        }

        LibSecp256k1.Point memory aggPubKey = LibMuSig2KeyAgg.aggregateKeys(signerPts);

        bool isValid = aggPubKey.verifySignature(
            message,
            schnorrData.signature,
            schnorrData.commitment
        );
        if (!isValid) revert("Invalid signature");
    }

    function _getPubKeys()
        internal
        view
        returns (LibSecp256k1.Point[] memory pubKeys)
    {
        PubkeysBlob memory blob = abi.decode(SSTORE2.read(pointer), (PubkeysBlob));
        pubKeys = blob.keys;
    }

    function _getNodeCount() internal view returns (uint256 nodeCount) {
        PubkeysBlob memory blob = abi.decode(SSTORE2.read(pointer), (PubkeysBlob));
        nodeCount = blob.keys.length - START_INDEX;
    }

    function _constructMessage(
        DataUpdate calldata dataUpdate
    ) internal pure returns (bytes32 message) {
        message = keccak256(
            abi.encodePacked(
                dataUpdate.jobId,
                dataUpdate.value,
                dataUpdate.timestamp
            )
        ).toEthSignedMessageHash();
    }

    function _zeroParticipationMapHash(uint256 nodeCount) internal pure returns (bytes32) {
        uint32[] memory z = new uint32[](nodeCount);
        return keccak256(abi.encode(z));
    }
}
