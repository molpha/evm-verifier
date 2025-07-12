// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title IFeedRegistryErrors - Errors for the FeedRegistry
/// @notice Errors for the FeedRegistry
interface IFeedRegistryErrors {
    /// @notice thrown when address is not feed
    /// @param addr address
    error NotFeed(address addr);

    /// @notice thrown when feed config is invalid
    error InvalidFeedConfig();
}