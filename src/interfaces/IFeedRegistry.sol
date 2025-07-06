// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {IFeed} from "./IFeed.sol";
import {IFeedRegistryEvents} from "./IFeedRegistryEvents.sol";
import {IFeedRegistryErrors} from "./IFeedRegistryErrors.sol";
import {IFeedRegistryStructs} from "./IFeedRegistryStructs.sol";

/// @title IFeedRegistry - Feed registration and lookup
/// @notice Registry of active feeds on the Molpha protocol
interface IFeedRegistry is IFeedRegistryEvents, IFeedRegistryErrors, IFeedRegistryStructs {
    /// @notice Create a new feed
    /// @param feedType The feed type   
    /// @param frequency The frequency of the feed
    /// @param minSignaturesThreshold The minimum number of signatures required for the feed
    /// @param ipfsCID The IPFS CID of the feed metadata
    function createFeed(IFeed.FeedType feedType, uint256 frequency, uint256 minSignaturesThreshold, string memory ipfsCID) external;

    /// @notice Check if a feed is registered
    /// @param feed The feed address
    /// @return isFeed True if the feed is registered
    function isFeed(address feed) external view returns (bool isFeed);
}
