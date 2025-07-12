// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {LibSecp256k1} from "../libs/LibSecp256k1.sol";

/// @title INodeRegistry
/// @notice Interface for the NodeRegistry
/// @dev INodeRegistry is repsponsible for managing node aggregators and
///      nodes registration/deregistration that includes security deposit and slashing
///      It is also responsible for adding nodes to aggregators and removing them
interface INodeRegistry {
    /// @notice Register a new node in the registry
    /// @param pubkey The public key of the node
    function registerNode(LibSecp256k1.Point memory pubkey) external;

    /// @notice Unregister a node from the registry
    /// @param node The address of the node
    function unregisterNode(address node) external;

    /// @notice Deploy a new aggregator
    function deployAggregator() external;

    /// @notice Add a node to an aggregator
    /// @param node The address of the node
    function addToAggregator(address node, address aggregator) external;

    /// @notice Remove a node from an aggregator
    /// @param node The address of the node
    /// @param aggregator The address of the aggregator
    function removeFromAggregator(address node, address aggregator) external;

    /// @notice Check if an aggregator is deployed
    /// @param aggregator The address of the aggregator
    /// @return isDeployed Whether the aggregator is deployed
    function isAggregator(address aggregator) external view returns (bool);

    /// @notice Get the index of a node
    /// @param node The address of the node
    /// @return index The index of the node
    function getNodeIndex(address node) external view returns (uint256 index);
}