// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title ISubscriptionsRegistryStructs
/// @notice Structs for the SubscriptionsRegistry
interface ISubscriptionsRegistryStructs {
    /// @notice Subscription struct
    /// @param dueTime subscription due time
    /// @param price subscription price
    struct Subscription {
        uint64 dueTime;
        uint128 price;
    }
}