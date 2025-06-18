// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title ISubscriptionsRegistryEvents
/// @notice Events for the SubscriptionsRegistry
interface ISubscriptionsRegistryEvents {
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
}
