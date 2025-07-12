// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {IFeed} from "./IFeed.sol";

/// @title IFeedRegistry - Feed registration and lookup
/// @notice Registry of active feeds on the Molpha protocol
interface IFeedRegistryEvents {

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
}
