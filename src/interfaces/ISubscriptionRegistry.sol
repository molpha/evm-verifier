// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title ISubscriptionRegistry - Manages feed subscriptions
/// @notice Tracks which consumers are subscribed to which feeds
interface ISubscriptionRegistry {
    /// @notice Subscribe to a feed
    /// @param feedId The feed to subscribe to
    /// @param months Number of months to pay for
    function subscribe(uint256 feedId, uint256 months) external payable;

    /// @notice Check if a user is currently subscribed
    /// @param user The address to check
    /// @param feedId The feed identifier
    /// @return isActive True if the subscription is active
    function isSubscribed(address user, uint256 feedId) external view returns (bool isActive);

    /// @notice Get subscription expiration timestamp
    /// @param user The address of the subscriber
    /// @param feedId The feed identifier
    /// @return expiration UNIX timestamp
    function getSubscriptionEnd(address user, uint256 feedId) external view returns (uint256 expiration);
}
