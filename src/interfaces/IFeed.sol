// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {ISubscriptionRegistry} from "./ISubscriptionRegistry.sol";
import {IFeedStructs} from "./IFeedStructs.sol";
import {IFeedEvents} from "./IFeedEvents.sol";
import {IFeedErrors} from "./IFeedErrors.sol";

/// @title IFeed - Interface for a data feed contract
/// @notice Handles feed metadata, update logic, and on-chain value access
/// @dev Implemented by specific feed contracts
interface IFeed is IFeedStructs, IFeedEvents, IFeedErrors {
    /// @notice Feed update configuration
    /// @param frequency The frequency of the feed
    /// @param signaturesRequired The minimum number of signatures required to verify an answer
    struct FeedPublishConfig {
        uint256 frequency;
        uint256 signaturesRequired;
    }

    /// @notice Feed type
    /// @param PUBLIC The public feed
    /// @param PERSONAL The personal feed
    enum FeedType {
        PUBLIC,
        PERSONAL
    }

    /// @notice Publish an answer
    /// @param answer The answer to publish
    function publish(Answer calldata answer) external;

    /// @notice Set the minimum number of signatures required to verify an answer
    /// @dev This function is only callable by the feed manager and only for personal feeds
    /// @param signaturesRequired The minimum number of signatures required
    function setMinSignaturesThreshold(uint256 signaturesRequired) external;

    /// @notice Set the frequency of the feed
    /// @dev This function is only callable by the feed manager and only for personal feeds
    /// @param frequency The frequency of the feed
    function setFrequency(uint256 frequency) external;

    /// @notice Set the IPFS CID of the feed
    /// @dev This function is only callable by the feed manager and only for personal feeds
    /// @param cid The IPFS CID of the feed
    function setCID(string calldata cid) external;

    /// @notice Update the feed configuration
    /// @dev This function is only callable by the feed manager and only for personal feeds
    /// @param frequency The frequency of the feed
    /// @param signaturesRequired The minimum number of signatures required
    /// @param cid The IPFS CID of the feed
    function updateFeedConfig(uint256 frequency, uint256 signaturesRequired, string calldata cid) external;

    /// @notice Returns the minimum number of signatures required to verify an answer
    /// @return signaturesRequired The minimum number of signatures required
    function getMinSignaturesThreshold() external view returns (uint256 signaturesRequired);

    /// @notice Returns the price per second scaled
    /// @return pricePerSecondScaled The price per second scaled
    function getPricePerSecondScaled() external view returns (uint256 pricePerSecondScaled);

    /// @notice Returns the feed owner
    /// @return owner The feed owner
    function getOwner() external view returns (address owner);

    /// @notice Returns the feed type
    /// @return feedType The feed type
    function getFeedType() external view returns (FeedType feedType);

    /// @notice Returns the latest feed data
    /// @return value The latest value
    /// @return timestamp Last update time
    function getLatest() external view returns (
        bytes memory value,
        uint256 timestamp
    );

    /// @notice Returns the last update timestamp
    /// @return timestamp UNIX timestamp of last update
    function getLastUpdated() external view returns (uint256 timestamp);

    /// @notice Returns the subscription registry
    /// @return subscriptionRegistry The subscription registry
    function getSubscriptionRegistry() external view returns (ISubscriptionRegistry subscriptionRegistry);

    /// @notice Returns the entry at a specific index
    /// @param index The index of the entry
    /// @return value The value at the index
    /// @return timestamp The timestamp at the index
    function getEntry(uint256 index) external view returns (bytes memory value, uint256 timestamp);
}