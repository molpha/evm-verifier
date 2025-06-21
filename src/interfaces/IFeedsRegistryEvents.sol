// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title IFeedsRegistry - Feed registration and lookup
/// @notice Registry of active feeds on the Molpha protocol
interface IFeedsRegistryEvents {

    /// @notice emitted when new feed is added
    /// @param feed new feed address
    event LogFeedCreated(address indexed feed);

    /// @notice emitted when feed subscription price is changed
    /// @param feed feed address
    /// @param newSubscriptionPrice new subscription price
    event LogSubscriptionPriceChanged(address indexed feed, uint256 newSubscriptionPrice);
}
