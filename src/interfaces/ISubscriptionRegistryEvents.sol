// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title ISubscriptionRegistryEvents
/// @notice Events for the SubscriptionRegistry
interface ISubscriptionRegistryEvents {
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

    /// @notice emitted when batch subscription is made
    /// @param subscribers array of subscriber addresses
    /// @param feed feed address
    /// @param dueTime subscription due time
    event LogBatchSubscribed(address[] indexed subscribers, address indexed feed, uint256 dueTime);

    /// @notice emitted when access is granted to a consumer for a personal feed
    /// @param consumer consumer address
    /// @param feed feed address
    /// @param owner feed owner address
    event LogPersonalFeedAccessGranted(address indexed consumer, address indexed feed, address indexed owner);

    /// @notice emitted when access is revoked from a consumer for a personal feed
    /// @param consumer consumer address
    /// @param feed feed address
    /// @param owner feed owner address
    event LogPersonalFeedAccessRevoked(address indexed consumer, address indexed feed, address indexed owner);

    /// @notice emitted when access is granted to a consumer for a feed
    /// @param consumer consumer address
    /// @param feed feed address
    /// @param owner feed owner address
    event LogAccessGranted(address indexed consumer, address indexed feed, address indexed owner);

    /// @notice emitted when access is revoked from a consumer for a feed
    /// @param consumer consumer address
    /// @param feed feed address
    /// @param owner feed owner address
    event LogAccessRevoked(address indexed consumer, address indexed feed, address indexed owner);

    /// @notice emitted when subscription is transferred to a new consumer
    /// @param consumer consumer address
    /// @param feed feed address
    /// @param newConsumer new consumer address
    event LogSubscriptionTransferred(address indexed consumer, address indexed feed, address indexed newConsumer);
}
