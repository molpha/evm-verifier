// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {LibSecp256k1} from "../libs/LibSecp256k1.sol";

/// @title IAggregator - Responsible for batching and submitting feed updates
/// @notice Aggregators collect signatures from nodes and submit them on-chain
interface INodeAggregator {
    /// @notice Submit a single feed update
    /// @param feedId Identifier of the feed
    /// @param value The new feed value
    /// @param timestamp UNIX timestamp
    /// @param signature Aggregated Schnorr signature
    /// @param bitmap 256-bit mask of participating nodes
    function submitSingle(
        uint256 feedId,
        uint256 value,
        uint256 timestamp,
        bytes calldata signature,
        uint256 bitmap
    ) external;

    // TODO: consider using single signature for batch submission
    /// @notice Submit multiple feed updates in a batch
    /// @param feedIds Array of feed identifiers
    /// @param values Array of feed values
    /// @param timestamps Array of UNIX timestamps
    /// @param signatures Array of aggregated Schnorr signatures
    /// @param bitmaps Array of 256-bit participation masks
    function submitBatch(
        uint256[] calldata feedIds,
        uint256[] calldata values,
        uint256[] calldata timestamps,
        bytes[] calldata signatures,
        uint256[] calldata bitmaps
    ) external;

    /// @notice Register a new node in the aggregator group
    /// @param pubkey Public key of the node
    function registerNode(LibSecp256k1.Point memory pubkey) external;

    /// @notice Unregister a node
    /// @param node Address of the node to remove
    function unregisterNode(address node) external;

    /// @notice Check if a node is currently registered
    /// @param node Address of the node
    /// @return isActive Whether the node is active
    function isNode(address node) external view returns (bool isActive);
}
