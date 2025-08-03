// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title ISubscriptionRegistryStructs
/// @notice Structs for the SubscriptionRegistry
interface ISubscriptionRegistryStructs {
    /// @notice Subscription struct
    /// @param dueTime subscription due time
    /// @param owner subscription owner
    struct Subscription {
        uint64 dueTime;
        address owner;
    }

    // struct ConsumerSubscription {
    //     address subscriptionOwner;
    //     address[] consumers;
    // }
}