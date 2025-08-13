// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {IFeed} from "./IFeed.sol";
import {IDataSourceRegistry} from "./IDataSourceRegistry.sol";

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
        uint64 frequency;
        uint64 minSignaturesThreshold;
        uint64 subscriptionDueTime;
        uint128 consumerPricePerSecondScaled;
        address[] defaultConsumers;
        bytes32 feedId;
        string ipfsCID;
    }

    /// @notice Parameters for creating a data source
    /// @param dataSource The data source to create
    /// @param signature The signature of the data source owner
    struct CreateDataSourceParams {
        IDataSourceRegistry.DataSource dataSource;
        bytes signature;
    }

    /// @notice emitted when new feed is added
    /// @param feed new feed address
    /// @param feedType feed type
    /// @param frequency feed frequency
    /// @param minSignaturesThreshold minimum number of signatures required
    /// @param feedId feed ID
    event LogFeedCreated(
        address indexed feed, 
        bytes32 indexed dataSourceId,
        bytes32 indexed feedId,
        uint256 activeTill,
        IFeed.FeedType feedType,
        uint256 frequency, 
        uint256 minSignaturesThreshold, 
        uint256 consumerPricePerSecondScaled,
        string ipfsCID
    );

    /// @notice Initialize the feed registry
    /// @param accessControlManager The access control manager address
    /// @param subscriptionRegistry The subscription registry address
    /// @param dataSourceRegistry The data source registry address
    function initialize(address accessControlManager, address subscriptionRegistry, address dataSourceRegistry) external;

    /// @notice Create a new feed with a new data source
    /// @param params The parameters for creating a feed
    function createFeedWithNewDataSource(CreateFeedParams calldata params, CreateDataSourceParams calldata dataSourceParams) external;

    /// @notice Create a new feed with an existing data source
    /// @param params The parameters for creating a feed
    /// @param dataSourceId The ID of the data source
    function createFeed(CreateFeedParams calldata params, bytes32 dataSourceId) external;

    /// @notice Update the feed configuration
    /// @param feed The feed address
    /// @param frequency The frequency of the feed
    /// @param signaturesRequired The minimum number of signatures required
    /// @param feedId The feed ID
    /// @param ipfsCID The IPFS CID of the feed metadata
    function updateFeed(address feed, uint256 frequency, uint256 signaturesRequired, bytes32 feedId, string calldata ipfsCID) external;

    /// @notice Set the access control manager
    /// @param accessControlManager The access control manager address
    function setAccessControlManager(address accessControlManager) external;

    /// @notice Set the subscription registry
    /// @param subscriptionRegistry The subscription registry address
    function setSubscriptionRegistry(address subscriptionRegistry) external;
}
