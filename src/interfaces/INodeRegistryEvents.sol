// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title INodeRegistryEvents
/// @notice Events for the NodeRegistry
interface INodeRegistryEvents {
    /// @notice Emitted when a new node is added to the set
    /// @param node The address of the new node
    /// @param index The index assigned to the new node
    /// @param pointer The storage pointer to the updated nodes array
    event LogNodeAdded(address indexed node, uint256 index, address pointer);

    /// @notice Emitted when a node is removed from the set
    /// @param node The address of the removed node
    /// @param oldIndex The previous index of the removed node
    /// @param pointer The storage pointer to the updated nodes array
    event LogNodeRemoved(address indexed node, uint256 oldIndex, address pointer);

    /// @notice Emitted when the minimum signatures threshold is updated
    /// @param newThreshold The new minimum number of signatures required
    event LogThresholdUpdated(uint256 newThreshold);
}
