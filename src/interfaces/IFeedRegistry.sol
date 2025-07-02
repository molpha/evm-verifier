// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

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
    function createFeed(FeedType feedType, uint256 frequency, uint256 minSignaturesThreshold, string memory ipfsCID) external;

    /// @notice Update the feed config
    /// @param feed The feed address
    /// @param frequency The frequency of the feed
    /// @param minSignaturesThreshold The minimum number of signatures required for the feed
    /// @param ipfsCID The IPFS CID of the feed metadata
    function updateFeedConfig(address feed, uint256 frequency, uint256 minSignaturesThreshold, string calldata ipfsCID) external;

    /// @notice Set the frequency of the feed
    /// @param feed The feed address
    /// @param frequency The frequency of the feed
    function setFrequency(address feed, uint256 frequency) external;

    /// @notice Set the minSignaturesThreshold of the feed
    /// @param feed The feed address
    /// @param minSignaturesThreshold The minimum number of signatures required for the feed
    function setMinSignaturesThreshold(address feed, uint256 minSignaturesThreshold) external;

    /// @notice Set CID of the feed
    /// @param feed The feed address
    /// @param ipfsCID The IPFS CID of the feed metadata
    function setCID(address feed, string calldata ipfsCID) external;

    /// @notice Check if a feed is registered
    /// @param feed The feed address
    /// @return isFeed True if the feed is registered
    function isFeed(address feed) external view returns (bool isFeed);

    /// @notice Get the feed config
    /// @param feed The feed address
    /// @return config The feed configuration
    function getFeedConfig(address feed) external view returns (FeedConfig memory config);

    /// @notice Get the feed price
    /// @param feed The feed address
    /// @return price The feed price
    function getFeedPrice(address feed) external view returns (uint256 price);
}
