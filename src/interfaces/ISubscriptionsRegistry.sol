// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title ISubscriptionRegistry - Manages feed subscriptions
/// @notice Tracks which consumers are subscribed to which feeds
interface ISubscriptionsRegistry {
    /// @notice Subscription struct
    /// @param dueTime subscription due time
    /// @param price subscription price
    struct Subscription {
        uint64 dueTime;
        uint128 price;
    }

     /// @notice thrown on unsubscribe call if remaining subscription time is less than minimum
    /// @param dueTime remaining subscription time
    error CannotUnsubscribe(uint256 dueTime);

    /// @notice thrown when someone tries to subscribe to wrong aggregator
    /// @param aggregator address of aggregator
    error NotAggregator(address aggregator);

    /// @notice thrown when subscription time is less than minimum or more than maximum
    /// @param timespan subscription time
    error WrongSubscriptionTime(uint256 timespan);

    /// @notice thrown when someone tries to set invalid subscription price
    /// @param price subscription price
    error WrongSubscriptionPrice(uint256 price);

    /// @notice thrown when someone tries to subscribe to already subscribed aggregator and price is different
    /// @dev in this case user extend subscription only when due time is less than minimum subscription time
    error CannotExtendSubscription();

    /// @notice thrown when sender is not feeds registry
    /// only feeds registry can set price for feed
    /// @param sender sender address
    error NotFeedsRegistry(address sender);

    /// @notice thrown when admin tries to set invalid subscription fee
    /// @param fee subscription fee
    error WrongSubscriptionFee(uint256 fee);

    /// @notice emitted when new subscription is made
    /// @param subscriber subscriber address
    /// @param aggregator aggregator address
    /// @param dueTime subscription due time
    event LogSubscribed(address indexed subscriber, address indexed aggregator, uint256 dueTime);

    /// @notice emitted when consumer unsubscribes from aggregator
    /// @param consumer consumer address
    /// @param aggregator aggregator address
    event LogUnsubscribed(address indexed consumer, address indexed aggregator);

    /// @notice emitted when subscription fee is set
    /// @param subscriptionFee subscription fee
    event LogSubscriptionFeeSet(uint256 indexed subscriptionFee);

    /// @notice emitted when subscription price is set
    /// @param aggregator aggregator address
    /// @param subscriptionPrice subscription price
    event LogSubscriptionPriceSet(address indexed aggregator, uint256 subscriptionPrice);

    /// @notice Subscribe to a feed
    /// @param consumer The consumer address
    /// @param feed The feed address
    /// @param timespan The timespan to subscribe for
    function subscribe(address consumer, address feed, uint256 timespan) external;

    /// @notice Unsubscribe from a feed
    /// @param feed The feed address
    function unsubscribe(address feed) external;

    /// @notice Set subscription price for a feed
    /// @param feed The feed address
    /// @param price The new subscription price
    function setSubscriptionPrice(address feed, uint128 price) external;
    
    /// @notice Set subscription fee
    /// @param fee The new subscription fee
    function setSubscriptionFee(uint256 fee) external;

    /// @notice Check if a user is currently subscribed
    /// @param user The address to check
    /// @param feed The feed address
    /// @return isActive True if the subscription is active
    function isSubscribed(address user, address feed) external view returns (bool isActive);

    /// @notice Get subscription price
    /// @param feed The feed address
    /// @return price subscription price
    function getSubscriptionPrice(address feed) external view returns (uint256 price);

    /// @notice Get subscription fee
    /// @return fee subscription fee
    function getSubscriptionFee() external view returns (uint256 fee);

    /// @notice Get subscription due time
    /// @param consumer The address of the subscriber
    /// @param aggregator The aggregator address
    /// @return dueTime subscription due time
    function getSubscriptionDueTime(address consumer, address aggregator) external view returns (uint256 dueTime);

}
