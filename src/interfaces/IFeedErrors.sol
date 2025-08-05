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

    /// @notice reverts when consumers and due times are not the same length
    error InvalidConsumersAndDueTimes();

    /// @notice reverts when consumer is already subscribed
    /// @param consumer consumer address
    error NotConsumer(address consumer);

    /// @notice reverts when due time is in the past
    /// @param dueTime due time
    error PastDueTime(uint256 dueTime);

    /// @notice reverts when roundId is invalid
    /// @param roundId roundId
    error InvalidRoundId(uint256 roundId);

    /// @notice reverts when data source ID is invalid
    /// @param dataSourceId data source ID
    error InvalidDataSourceId(bytes32 dataSourceId);
}
