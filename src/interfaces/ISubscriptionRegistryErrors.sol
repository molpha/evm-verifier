// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {ICommonErrors} from "./ICommonErrors.sol";

/// @title ISubscriptionRegistryErrors
/// @notice Errors for the SubscriptionRegistry
interface ISubscriptionRegistryErrors is ICommonErrors {
     /// @notice thrown on unsubscribe call if remaining subscription time is less than minimum
    /// @param dueTime remaining subscription time
    error CannotUnsubscribe(uint256 dueTime);

    /// @notice thrown when someone tries to subscribe to wrong feed
    /// @param feed address of feed
    error NotFeed(address feed);

    /// @notice thrown when someone tries to subscribe to personal feed without permission
    /// @param feed address of feed
    error NotPersonalFeed(address feed);

    /// @notice thrown when someone tries to subscribe to public feed with personal feed price
    /// @param feed address of feed
    error NotPublicFeed(address feed);

    /// @notice thrown when subscription time is less than minimum or more than maximum
    /// @param timespan subscription time
    error WrongSubscriptionTime(uint256 timespan);

    /// @notice thrown when someone tries to set invalid subscription price
    /// @param price subscription price
    error WrongSubscriptionPrice(uint256 price);

    /// @notice thrown when someone tries to subscribe to already subscribed feed and price is different
    /// @dev in this case user extend subscription only when due time is less than minimum subscription time
    error CannotExtendSubscription();

    /// @notice thrown when sender is not feed registry
    /// only feed registry can set price for feed
    /// @param sender sender address
    error NotFeedRegistry(address sender);

    /// @notice thrown when admin tries to set invalid subscription fee
    /// @param fee subscription fee
    error WrongSubscriptionFee(uint256 fee);

    /// @notice thrown when sender is not subscription owner
    /// @param sender sender address
    error NotSubscriptionOwner(address sender);

    /// @notice thrown when batch subscribe array is empty
    error EmptyBatchSubscribe();

    /// @notice thrown when trying to access personal feed without permission
    /// @param consumer consumer address
    /// @param feed feed address
    error NoPersonalFeedAccess(address consumer, address feed);

    /// @notice thrown when sender is not the feed owner
    /// @param sender sender address
    /// @param feed feed address
    error NotFeedOwner(address sender, address feed);

    /// @notice thrown when personal feed main subscription is expired
    /// @param feed feed address
    error PersonalFeedMainSubscriptionExpired(address feed);
}
