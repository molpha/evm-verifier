// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {LibSecp256k1} from "../libs/LibSecp256k1.sol";
import {INodesAggregatorStructs} from "./INodesAggregatorStructs.sol";
import {INodesAggregatorEvents} from "./INodesAggregatorEvents.sol";
import {INodesAggregatorErrors} from "./INodesAggregatorErrors.sol";

/// @title INodesAggregator
/// @notice Interface for the NodesAggregator
interface INodesAggregator is INodesAggregatorStructs, INodesAggregatorEvents, INodesAggregatorErrors {
    /// @notice Add a new node in the aggregator group
    /// @param pubkey Public key of the node
    function addNode(LibSecp256k1.Point memory pubkey) external;

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

    /// @notice Verify a Schnorr signature
    /// @param message The message to verify
    /// @param schnorrData The Schnorr signature data
    /// @param minSignaturesThreshold The minimum number of signatures required
    function verifySignature(
        bytes32 message,
        SchnorrSignature calldata schnorrData,
        uint256 minSignaturesThreshold
    ) external view;
}
