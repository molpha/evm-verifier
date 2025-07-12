// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {IFeed} from "./IFeed.sol";
import {IFeedRegistryEvents} from "./IFeedRegistryEvents.sol";
import {IFeedRegistryErrors} from "./IFeedRegistryErrors.sol";

/// @title IFeedRegistry - Feed registration and lookup
/// @notice Registry of active feeds on the Molpha protocol
interface IFeedRegistry is IFeedRegistryEvents, IFeedRegistryErrors
{
    /// @notice Create a new feed
    /// @param frequency The frequency of the feed
    /// @param minSignaturesThreshold The minimum number of signatures required for the feed
    /// @param ipfsCID The IPFS CID of the feed metadata
    /// @param defaultConsumer The default consumer of the feed
    /// @param subscriptionDueTime The due time of the subscription
    function createPublicFeed(
        uint256 frequency,
        uint256 minSignaturesThreshold,
        string memory ipfsCID,
        address defaultConsumer,
        uint256 subscriptionDueTime
    ) external;

    /// @notice Create a new personal feed
    /// @param frequency The frequency of the feed
    /// @param minSignaturesThreshold The minimum number of signatures required for the feed
    /// @param ipfsCID The IPFS CID of the feed metadata
    /// @param subscriptionDueTime The due time of the subscription
    function createPersonalFeed(
        uint256 frequency,
        uint256 minSignaturesThreshold,
        string memory ipfsCID,
        uint256 subscriptionDueTime
    ) external;
}
