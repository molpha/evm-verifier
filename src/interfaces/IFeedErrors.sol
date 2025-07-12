// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {ICommonErrors} from "./ICommonErrors.sol";

/// @title IFeedErrors
/// @notice Errors for the Feed contract
interface IFeedErrors is ICommonErrors {
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

    /// @notice reverts when min signatures threshold is immutable
    /// @dev This error is thrown when trying to set the min signatures threshold for a public feed
    error ImmutableThreshold();

    /// @notice reverts when feed is not personal
    /// @dev This error is thrown when trying to set the min signatures threshold for a public feed
    error NotPersonalFeed();

    /// @notice reverts when frequency is invalid
    /// @param frequency frequency
    error InvalidFrequency(uint256 frequency);

    /// @notice reverts when min signatures threshold is invalid
    /// @param signaturesRequired min signatures threshold
    error InvalidMinSignaturesThreshold(uint256 signaturesRequired);

    /// @notice reverts when CID is invalid
    /// @param ipfsCID CID
    error InvalidCID(string ipfsCID);

    /// @notice reverts when msg sender is not the feed owner
    /// @param sender sender address
    error NotFeedOwner(address sender);

    /// @notice reverts when feed function is not supported
    error NotSupported();
}
