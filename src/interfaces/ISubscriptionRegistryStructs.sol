// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title ISubscriptionRegistryStructs
/// @notice Structs for the SubscriptionRegistry
interface ISubscriptionRegistryStructs {
    /// @notice Subscription struct
    /// @param dueTime subscription due time
    /// @param price subscription price
    /// @param owner subscription owner
    struct Subscription {
        uint64 dueTime;
        // uint128 price;
        address owner;
    }

    /// @notice Batch subscribe parameters
    /// @param consumers Array of consumer addresses to subscribe
    /// @param feed The feed address
    /// @param timespan The timespan to subscribe for
    struct BatchSubscribeParams {
        address[] consumers;
        address feed;
        uint256 timespan;
    }
}