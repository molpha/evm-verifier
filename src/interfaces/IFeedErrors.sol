// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {INodeAggregator} from "./INodeAggregator.sol";
import {ISubscriptionRegistry} from "./ISubscriptionRegistry.sol";

/// @title IFeedErrors
/// @notice Errors for the Feed contract
interface IFeedErrors {
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
    error NotNodeRegistry(address sender);
}
