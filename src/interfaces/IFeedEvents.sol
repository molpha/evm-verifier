// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title IFeedEvents
/// @notice Events for the Feed contract
interface IFeedEvents {
    /// @notice emitted when new answer is published
    /// @param value new answer value
    /// @param timestamp new answer timestamp
    event LogAnswerPublished(bytes value, uint64 indexed timestamp);

    /// @notice emitted when feed config is changed
    /// @param frequency new frequency
    /// @param minSignaturesThreshold new minSignaturesThreshold
    event LogFeedConfigChanged(uint256 frequency, uint256 minSignaturesThreshold);

    /// @notice emitted when consumers are set
    /// @param consumersToAdd consumers to add
    /// @param dueTime due time
    /// @param consumersToRemove consumers to remove
    event LogConsumersSet(address[] consumersToAdd, uint256 dueTime, address[] consumersToRemove);
}
