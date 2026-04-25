// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.31;

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


    /// @notice Initializes a job's seed and round counter.
    /// @dev    startTime MUST be identical across all deployment chains for a given jobId.
    ///        Using any chain-specific value (block.chainid, block.timestamp) would cause
    ///        permanent seed divergence. The initial seed is keccak256(jobId || 0 || startTime).
    /// @param jobId    The job identifier.
    /// @param startTime Canonical start timestamp supplied by the admin; must match on all chains.
    function initializeJob(bytes32 jobId, uint64 startTime) external;

    /// @notice Round counter for a job (from stored job state)
    function getJobRound(bytes32 jobId) external view returns (uint32 round);

    /// @notice Current seed for a job (from stored job state)
    function getJobSeed(bytes32 jobId) external view returns (bytes32 seed);

    /// @notice Selection group size for a feed's signature requirement
    function getGroupSize(uint256 signaturesRequired) external view returns (uint256 groupSize);

    /// @notice Add a new node in the aggregator group
    /// @param compressedPubKey Compressed public key of the node
    /// @param popSignature Proof-of-possession signature by the same key over the registration domain message
    function addNode(bytes memory compressedPubKey, bytes memory popSignature) external;

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

    /// @notice Plain-sum aggregate pubkey over the full registered signer set (uncompressed x, y)
    function getAggregateKey() external view returns (uint256 x, uint256 y);

    /// @notice Verify a Schnorr signature
    /// @param message The message to verify
    /// @param schnorrData The Schnorr signature data
    /// @param minSignaturesThreshold The minimum number of signatures required
    /// @param round Job round
    /// @param seed Job seed
    /// @param nodeCount Number of nodes in the set
    /// @notice Reverts if verification fails. Not `view`: publish path records participation in the same pass.
    function verifySignature(
        bytes32 message,
        SchnorrSignature calldata schnorrData,
        uint256 minSignaturesThreshold,
        uint32 round,
        bytes32 seed,
        uint256 nodeCount
    ) external;

    /// @notice Get the index of a node (alternative name for compatibility)
    /// @param node Address of the node
    /// @return index The index of the node
    function getNodeIndex(address node) external view returns (uint256 index);
}
