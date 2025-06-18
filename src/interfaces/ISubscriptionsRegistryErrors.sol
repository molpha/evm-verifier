// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title ISubscriptionsRegistryErrors
/// @notice Errors for the SubscriptionsRegistry
interface ISubscriptionsRegistryErrors {
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
}
