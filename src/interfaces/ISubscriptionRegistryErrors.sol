// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {ICommonErrors} from "./ICommonErrors.sol";

/// @title ISubscriptionRegistryErrors
/// @notice Errors for the SubscriptionRegistry
interface ISubscriptionRegistryErrors is ICommonErrors {
    /// @notice thrown when sender tries to subscribe to feed
    error CannotSubscribe();

    /// @notice thrown when someone tries to subscribe to wrong feed
    /// @param feed address of feed
    error NotFeed(address feed);

    /// @notice thrown when subscription time is less than minimum or more than maximum
    /// @param timespan subscription time
    error WrongSubscriptionTime(uint256 timespan);

    /// @notice thrown when someone tries to subscribe to already subscribed feed and price is different
    /// @dev in this case user extend subscription only when due time is less than minimum subscription time
    error CannotExtendSubscription();

    /// @notice thrown when sender is not subscription owner
    /// @param sender sender address
    error NotSubscriptionOwner(address sender);

    /// @notice thrown when sender is not the feed owner
    /// @param sender sender address
    /// @param feed feed address
    error NotFeedOwner(address sender, address feed);

    /// @notice thrown when subscription already exists
    /// @param consumer consumer address
    /// @param feed feed address
    error SubscriptionAlreadyExists(address consumer, address feed);

    /// @notice thrown when consumers array is empty
    error EmptyConsumers();

    /// @notice thrown when trying to transfer subscription with invalid subscription type
    error CannotTransferSubscription();

    /// @notice thrown when consumer address is already subscribed to feed
    /// @param consumer consumer address
    /// @param feed feed address
    /// @param dueTime due time
    error ConsumerAlreadySubscribed(address consumer, address feed, uint256 dueTime);

    /// @notice thrown when underlying token is invalid
    error InvalidUnderlying();
}
