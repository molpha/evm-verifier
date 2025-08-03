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

    /// @notice Update the access status of multiple consumers
    /// @dev This function is only callable by the feed owner or the subscription registry
    /// @notice The due time define if the access is granted or revoked
    /// @param consumersToAdd The consumers to grant access to
    /// @param dueTime The due time of the access
    /// @param consumersToRemove The consumers to revoke access from
    function setConsumers(address[] calldata consumersToAdd, uint256 dueTime, address[] calldata consumersToRemove) external;

    /// @notice Add a consumer to the feed
    /// @param consumer The consumer to add
    /// @param dueTime The due time of the access
    function addConsumer(address consumer, uint256 dueTime) external;

    /// @notice Remove a consumer from the feed
    /// @param consumer The consumer to remove
    function removeConsumer(address consumer) external;

    /// @notice Update the feed configuration
    /// @dev This function is only callable by the feed manager and only for personal feeds
    /// @param frequency The frequency of the feed
    /// @param signaturesRequired The minimum number of signatures required
    /// @param cid The IPFS CID of the feed
    function updateFeedConfig(uint256 frequency, uint256 signaturesRequired, string calldata cid) external;

    /// @notice Returns the minimum number of signatures required to verify an answer
    /// @return signaturesRequired The minimum number of signatures required
    function getMinSignaturesThreshold() external view returns (uint256 signaturesRequired);

    /// @notice Returns the frequency of the feed
    /// @return frequency The frequency of the feed
    function getFrequency() external view returns (uint256 frequency);

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

    /// @notice Returns the entry at a specific index
    /// @param index The index of the entry
    /// @return value The value at the index
    /// @return timestamp The timestamp at the index
    function getEntry(uint256 index) external view returns (bytes memory value, uint256 timestamp);
}