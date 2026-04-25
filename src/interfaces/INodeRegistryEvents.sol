// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.31;

/// @title INodeRegistryEvents
/// @notice Events for the NodeRegistry
interface INodeRegistryEvents {
    /// @notice Emitted when a new node is added to the set
    /// @param node The address of the new node
    /// @param index The index assigned to the new node
    /// @param rawKeysPointer The storage pointer to the updated raw keys array
    event LogNodeAdded(address indexed node, uint256 index, address rawKeysPointer);

    /// @notice Emitted when a node is removed from the set
    /// @param node The address of the removed node
    /// @param oldIndex The previous index of the removed node
    /// @param rawKeysPointer The storage pointer to the updated raw keys array
    event LogNodeRemoved(address indexed node, uint256 oldIndex, address rawKeysPointer);
    

    /// @notice Emitted when the minimum signatures threshold is updated
    /// @param newThreshold The new minimum number of signatures required
    event LogThresholdUpdated(uint256 newThreshold);

    /// @notice Emitted after a successful publish to a feed
    event LogAnswerPublished(
        address indexed feed,
        bytes value,
        uint64 timestamp,
        bytes32 signersBitmap,
        uint32 round,
        bytes32 seed
    );

    /// @notice Emitted when the global participation map hash is updated
    event LogParticipationUpdated(bytes32 newHash, uint32[] updatedMap);

    /// @notice Emitted when per-job oracle state is first initialized
    event LogJobInitialized(bytes32 indexed jobId, bytes32 initialSeed);
}
