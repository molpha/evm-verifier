// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title IFeedsRegistryErrors - Errors for the FeedsRegistry
/// @notice Errors for the FeedsRegistry
interface IFeedsRegistryErrors {
    /// @notice thrown when address is not feed
    /// @param addr address
    error NotFeed(address addr);
}