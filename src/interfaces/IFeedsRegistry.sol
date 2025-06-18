// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {IFeedsFactory} from "./IFeedsFactory.sol";

/// @title IFeedsRegistry - Feed registration and lookup
/// @notice Registry of active feeds on the Molpha protocol
interface IFeedsRegistry {
    /// @notice thrown when address is not feed
    /// @param addr address
    error NotFeed(address addr);

    /// @notice emitted when new feed is added
    /// @param feed new feed address
    event LogFeedCreated(address indexed feed);

    /// @notice emitted when feed subscription price is changed
    /// @param feed feed address
    /// @param newSubscriptionPrice new subscription price
    event LogSubscriptionPriceChanged(address indexed feed, uint256 newSubscriptionPrice);

    /// @notice Create a new feed
    /// @param metadataHash Hash of the feed metadata stored off-chain (IPFS/Arweave)
    /// @param rewardForAnswer The reward for an answer
    /// @param subscriptionPrice The price of the subscription
    /// @param minSignaturesThreshold The minimum number of signatures required to verify an answer
    /// @return feed The address of the feed
    function createFeed(bytes32 metadataHash, uint256 rewardForAnswer, uint128 subscriptionPrice, uint256 minSignaturesThreshold) external returns (address feed);

    /// @notice Set the subscription price for a feed
    /// @param feed The feed address
    /// @param price The new subscription price
    function setSubscriptionPrice(address feed, uint128 price) external;

    /// @notice Check if a feed is registered
    /// @param feed The feed address
    /// @return isFeed True if the feed is registered
    function isFeed(address feed) external view returns (bool isFeed);

    /// @notice Get the factory address
    /// @return factory The address of the factory
    function getFeedsFactory() external view returns (IFeedsFactory factory);
}
