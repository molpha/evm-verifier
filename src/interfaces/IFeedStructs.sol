// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.31;

/// @title IFeedStructs
/// @notice Structs for the Feed contract
interface IFeedStructs {
    /// @notice Aggregator answer struct
    /// @param value answer value
    /// @param timestamp answer timestamp
    struct Answer {
        bytes value;
        uint64 timestamp;
    }
}
