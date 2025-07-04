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
        uint128 price;
        address owner;
    }

    /// @notice Personal feed subscription struct
    /// @dev For personal feeds, the feed owner maintains the main subscription
    /// and grants access to multiple consumers
    /// @param mainSubscription The main subscription owned by the feed owner
    /// @param consumerAccess Mapping of consumer addresses to their access status
    struct PersonalFeedSubscription {
        Subscription mainSubscription;
        mapping(address => bool) consumerAccess;
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