// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {IFeed} from "./IFeed.sol";

/// @title IFeedRegistry - Feed registration and lookup
/// @notice Registry of active feeds on the Molpha protocol
interface IFeedRegistry
{
    /// @notice Parameters for creating a feed
    /// @param feedType The type of feed to create
    /// @param frequency The frequency of the feed
    /// @param minSignaturesThreshold The minimum number of signatures required
    /// @param ipfsCID The ipfsCID of the feed
    /// @param defaultConsumers The default consumers of the feed
    /// @param subscriptionDueTime The subscription due time
    struct CreateFeedParams {
        IFeed.FeedType feedType;
        uint256 frequency;
        uint256 minSignaturesThreshold;
        string ipfsCID;
        address[] defaultConsumers;
        uint256 subscriptionDueTime;
        uint256 consumerPricePerSecondScaled;
    }

    /// @notice emitted when new feed is added
    /// @param feed new feed address
    /// @param feedType feed type
    /// @param frequency feed frequency
    /// @param minSignaturesThreshold minimum number of signatures required
    /// @param ipfsCID ipfsCID
    event LogFeedCreated(
        address indexed feed, 
        IFeed.FeedType feedType,
        uint256 frequency, 
        uint256 minSignaturesThreshold, 
        string ipfsCID
    );

    /// @notice thrown when feed config is invalid
    error InvalidFeedConfig();

    /// @notice Initialize the feed registry
    /// @param accessControlManager The access control manager address
    /// @param subscriptionRegistry The subscription registry address
    function initialize(address accessControlManager, address subscriptionRegistry) external;

    /// @notice Create a new feed
    /// @param params The parameters for creating a feed
    function createFeed(CreateFeedParams calldata params) external;

    /// @notice Update the feed configuration
    /// @param feed The feed address
    /// @param frequency The frequency of the feed
    /// @param signaturesRequired The minimum number of signatures required
    /// @param ipfsCID The ipfsCID of the feed
    function updateFeed(address feed, uint256 frequency, uint256 signaturesRequired, string calldata ipfsCID) external;

    /// @notice Set the access control manager
    /// @param accessControlManager The access control manager address
    function setAccessControlManager(address accessControlManager) external;

    /// @notice Set the subscription registry
    /// @param subscriptionRegistry The subscription registry address
    function setSubscriptionRegistry(address subscriptionRegistry) external;

    /// @notice Check if a feed exists
    /// @param feed The feed address
    /// @return True if the feed exists, false otherwise
    // function isFeed(address feed) external view returns (bool);
}
