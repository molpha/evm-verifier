// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title IFeedEvents
/// @notice Events for the Feed contract
interface IFeedEvents {
    /// @notice emitted when new answer is published
    /// @param value new answer value
    /// @param timestamp new answer timestamp
    event LogAnswerPublished(bytes value, uint64 indexed timestamp);
}
