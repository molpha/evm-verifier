// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {ISubscriptionRegistryStructs} from "./ISubscriptionRegistryStructs.sol";
import {ISubscriptionRegistryEvents} from "./ISubscriptionRegistryEvents.sol";
import {ISubscriptionRegistryErrors} from "./ISubscriptionRegistryErrors.sol";

/// @title ISubscriptionRegistry - Manages feed subscriptions
/// @notice Tracks which consumers are subscribed to which feeds
interface ISubscriptionRegistry is ISubscriptionRegistryStructs, ISubscriptionRegistryEvents, ISubscriptionRegistryErrors {
    /// @notice Subscribe to a feed
    /// @param consumer The consumer address
    /// @param feed The feed address
    /// @param timespan The timespan to subscribe for
    function subscribe(address consumer, address feed, uint256 timespan) external;

    /// @notice Batch subscribe multiple consumers to a feed
    /// @param consumers Array of consumer addresses
    /// @param feed The feed address
    /// @param timespan The timespan to subscribe for
    function batchSubscribe(address[] calldata consumers, address feed, uint256 timespan) external;

    /// @notice Unsubscribe from a feed
    /// @param feed The feed address
    /// @param consumer The consumer address
    function unsubscribe(address feed, address consumer) external;

    /// @notice Check if a user is currently subscribed
    /// @param user The address to check
    /// @param feed The feed address
    /// @return isActive True if the subscription is active
    function isSubscribed(address user, address feed) external view returns (bool isActive);

    /// @notice Get subscription price
    /// @param feed The feed address
    /// @return price subscription price
    function getSubscriptionPrice(address feed) external view returns (uint256 price);

    /// @notice Get subscription due time
    /// @param consumer The address of the subscriber
    /// @param aggregator The aggregator address
    /// @return dueTime subscription due time
    function getSubscriptionDueTime(address consumer, address aggregator) external view returns (uint256 dueTime);

    /// @notice Grant access to a consumer for a personal feed (only feed owner can call)
    /// @param consumer The consumer address
    /// @param feed The personal feed address
    function grantPersonalFeedAccess(address consumer, address feed) external;

    /// @notice Revoke access from a consumer for a personal feed (only feed owner can call)
    /// @param consumer The consumer address
    /// @param feed The personal feed address
    function revokePersonalFeedAccess(address consumer, address feed) external;

    /// @notice Check if a consumer has access to a personal feed
    /// @param consumer The consumer address
    /// @param feed The personal feed address
    /// @return hasAccess True if the consumer has access
    function hasPersonalFeedAccess(address consumer, address feed) external view returns (bool hasAccess);
}
