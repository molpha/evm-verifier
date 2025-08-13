// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title ISubscriptionRegistryEvents
/// @notice Events for the SubscriptionRegistry
interface ISubscriptionRegistryEvents {
    /// @notice emitted when new subscription is made
    /// @param subscriber subscriber address
    /// @param feed feed address
    /// @param owner owner address
    /// @param dueTime subscription due time
    event LogSubscribed(
        address indexed subscriber,
        address indexed feed,
        address indexed owner,
        uint256 dueTime,
        uint256 pricePerSecondScaled
    );

    /// @notice emitted when consumer unsubscribes from feed
    /// @param consumer consumer address
    /// @param feed feed address
    event LogUnsubscribed(address indexed consumer, address indexed feed);

    /// @notice emitted when subscription is transferred to a new consumer
    /// @param consumer consumer address
    /// @param feed feed address
    /// @param newConsumer new consumer address
    /// @param dueTime subscription due time
    event LogSubscriptionTransferred(
        address indexed consumer,
        address indexed feed,
        address indexed newConsumer,
        uint64 dueTime
    );

    /// @notice emitted when subscription is extended
    /// @param subscriber subscriber address
    /// @param feed feed address
    /// @param dueTime subscription due time
    event LogSubscriptionExtended(
        address indexed subscriber,
        address indexed feed,
        uint256 dueTime
    );

    /// @notice emitted when subscription is updated
    /// @param feed feed address
    /// @param subscriber subscriber address
    /// @param newDueTime new due time
    /// @param newPricePerSecondScaled new price per second scaled
    event LogSubscriptionUpdated(
        address indexed feed,
        address indexed subscriber,
        uint256 newDueTime,
        uint256 newPricePerSecondScaled
    );
}
