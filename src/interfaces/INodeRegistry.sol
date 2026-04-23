// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {LibSecp256k1} from "../libs/LibSecp256k1.sol";
import {INodeRegistryStructs} from "./INodeRegistryStructs.sol";
import {INodeRegistryEvents} from "./INodeRegistryEvents.sol";

/// @title INodeRegistry
/// @notice Interface for the NodeAggregator
interface INodeRegistry is INodeRegistryStructs, INodeRegistryEvents {
    /// @notice Initialize the node registry
    /// @param accessControlManager The access control manager address
    function initialize(address accessControlManager) external;

    /// @notice Publish a signed answer; verifies round, participation map, Schnorr, and selection bitmap
    function publish(
        DataUpdate calldata dataUpdate,
        SchnorrSignature calldata schnorrData
    ) external;

    /// @notice Initialize per-job seed and round counter (round 0)
    /// @param jobId The job identifier
    function initializeJob(bytes32 jobId) external;

    /// @notice Round counter for a job (from stored job state)
    function getJobRound(bytes32 jobId) external view returns (uint32 round);

    /// @notice Current seed for a job (from stored job state)
    function getJobSeed(bytes32 jobId) external view returns (bytes32 seed);

    /// @notice Selection group size for a feed's signature requirement
    function getGroupSize(uint256 signaturesRequired) external view returns (uint256 groupSize);

    /// @notice Add a new node in the aggregator group
    /// @param compressedPubKey Compressed public key of the node
    function addNode(bytes memory compressedPubKey) external;

    /// @notice Remove a node from the aggregator group
    /// @param node Address of the node to remove
    function removeNode(address node) external;

    /// @notice Check if a node is currently registered
    /// @param node Address of the node
    /// @return isActive Whether the node is active
    function isNode(address node) external view returns (bool isActive);

    /// @notice Get the total number of nodes in the aggregator group
    /// @return totalNodes The total number of nodes
    function getTotalNodes() external view returns (uint256 totalNodes);

    /// @notice Get the hash of the nodes set
    /// @return hash The hash of the nodes set
    function getNodesSetHash() external view returns (bytes32 hash);

    /// @notice Cumulative successful `publish` count for the node at 1-based registry index
    function participationCounts(uint256 nodeIndex) external view returns (uint256);

    /// @notice MuSig2 delinearized aggregate pubkey over the full registered signer set (uncompressed x, y)
    function getMuSigAggregateKey() external view returns (uint256 x, uint256 y);

    /// @notice Verify a Schnorr signature
    /// @param message The message to verify
    /// @param schnorrData The Schnorr signature data
    /// @param minSignaturesThreshold The minimum number of signatures required
    /// @param round Job round
    /// @param seed Job seed
    /// @param nodeCount Number of nodes in the set
    function verifySignature(
        bytes32 message,
        SchnorrSignature calldata schnorrData,
        uint256 minSignaturesThreshold,
        uint32 round,
        bytes32 seed,
        uint256 nodeCount
    ) external view;

    /// @notice Get the index of a node (alternative name for compatibility)
    /// @param node Address of the node
    /// @return index The index of the node
    function getNodeIndex(address node) external view returns (uint256 index);
}
