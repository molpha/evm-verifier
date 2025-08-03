// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {ISubscriptionRegistryStructs} from "./ISubscriptionRegistryStructs.sol";
import {ISubscriptionRegistryEvents} from "./ISubscriptionRegistryEvents.sol";
import {ISubscriptionRegistryErrors} from "./ISubscriptionRegistryErrors.sol";

/// @title ISubscriptionRegistry - Manages feed subscriptions
/// @notice Tracks which consumers are subscribed to which feeds
interface ISubscriptionRegistry is ISubscriptionRegistryStructs, ISubscriptionRegistryEvents, ISubscriptionRegistryErrors {
    /// @notice Initialize the subscription registry
    /// @param accessControlManager The access control manager address
    /// @param treasury The treasury address
    /// @param pricingHelper The pricing helper address
    function initialize(address accessControlManager, address treasury, address pricingHelper) external;

    /// @notice Set the feed registry
    /// @notice Subscribe to a feed
    /// @param feed The feed address
    /// @param dueTime The due time of the subscription 
    /// @param consumers The consumers to subscribe
    function subscribe(address feed, uint256 dueTime, address[] calldata consumers) external;

    /// @notice Create an owner subscription
    /// @param feed The feed address
    /// @param owner The owner address
    /// @param dueTime The due time of the subscription
    /// @param consumers The consumers to subscribe
    function initFeedSubscription(address feed, address owner, uint256 dueTime, address[] calldata consumers) external;

    /// @notice Unsubscribe from a feed
    /// @param feed The feed address
    /// @param consumer The consumer address
    // function unsubscribe(address feed, address consumer) external;

    /// @notice Extend subscription
    /// @param consumer The consumer address
    /// @param feed The feed address
    /// @param dueTime The due time of the subscription
    function extendSubscription(address consumer, address feed, uint256 dueTime) external;

    /// @notice Transfer subscription to a new consumer
    /// @param consumer The consumer address
    /// @param feed The feed address
    /// @param newConsumer The new consumer address
    function transferSubscription(address consumer, address feed, address newConsumer) external;

    /// @notice Recalculate the subscription
    /// @param feed The feed address
    function recalculateSubscription(address feed) external;

    /// @notice Set the consumer price per second scaled
    /// @param feed The feed address
    /// @param consumerPricePerSecondScaled The consumer price per second scaled
    function setConsumerPricePerSecondScaled(address feed, uint256 consumerPricePerSecondScaled) external;

    /// @notice Set the treasury
    /// @param treasury The treasury address
    function setTreasury(address treasury) external;

    /// @notice Get subscription
    /// @param consumer The consumer address
    /// @param feed The feed address
    /// @return subscription The subscription
    function getSubscription(address consumer, address feed) external view returns (Subscription memory subscription);
}
