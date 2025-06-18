// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {INodesAggregator} from "./INodesAggregator.sol";
import {ISubscriptionsRegistry} from "./ISubscriptionsRegistry.sol";

/// @title IFeed - Interface for a data feed contract
/// @notice Handles feed metadata, update logic, and on-chain value access
/// @dev Implemented by specific feed contracts
interface IFeed {
    /// @notice Aggregator answer struct
    /// @param value answer value
    /// @param timestamp answer timestamp
    struct Answer {
        bytes value;
        uint64 timestamp;
    }

    /// @notice reverts in publishAnswer() when timestamp is <= last published timestamp
    /// @param timestamp new answer timestamp
    /// @param lastTimestamp last published answer timestamp
    error PastTimestamp(uint256 timestamp, uint256 lastTimestamp);

    /// @notice reverts in publishAnswer() when timestamp is > block timestamp
    /// @param timestamp new answer timestamp
    /// @param blockTimestamp block timestamp
    error FutureTimestamp(uint256 timestamp, uint256 blockTimestamp);

    /// @notice reverts consumer is not subscribed to the aggregator
    /// @param consumer consumer address
    error NotSubscribed(address consumer);

    /// @notice reverts when msg sender is not a nodes registry
    /// only a nodes registry can add or remove nodes
    /// @param sender sender address
    error NotNodesRegistry(address sender);

    /// @notice emitted when new answer is published
    /// @param value new answer value
    /// @param timestamp new answer timestamp
    event LogAnswerPublished(bytes value, uint64 indexed timestamp);

    /// @notice Publish an answer
    /// @param answer The answer to publish
    /// @param schnorrData The Schnorr signature data
    function publishAnswer(Answer calldata answer, INodesAggregator.SchnorrSignature calldata schnorrData) external;

    /// @notice Returns the latest feed data
    /// @return value The latest value
    /// @return timestamp Last update time
    function getLatest() external view returns (
        bytes memory value,
        uint256 timestamp
    );

    /// @notice Returns the last update timestamp
    /// @return timestamp UNIX timestamp of last update
    function getLastUpdated() external view returns (uint256 timestamp);

    /// @notice Returns the subscriptions registry
    /// @return subscriptionsRegistry The subscriptions registry
    function getSubscriptionsRegistry() external view returns (ISubscriptionsRegistry subscriptionsRegistry);

    /// @notice Returns the entry at a specific index
    /// @param index The index of the entry
    /// @return value The value of the entry
    /// @return timestamp The timestamp of the entry
    function getEntry(uint256 index) external view returns (bytes memory value, uint256 timestamp);
}
