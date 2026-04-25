// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.31;

/// @title ISubscriptionRegistryStructs
/// @notice Structs for the SubscriptionRegistry
interface ISubscriptionRegistryStructs {
    /// @notice Subscription struct
    /// @param dueTime subscription due time
    /// @param owner subscription owner
    struct Subscription {
        address owner;
        uint64 dueTime;
        SubscriptionType subscriptionType;
    }

    /// @notice Subscription type
    enum SubscriptionType {
        Owner,
        Consumer
    }
}
