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

    /// @notice emitted when feed subscription price is changed
    /// @param feed feed address
    /// @param newSubscriptionPrice new subscription price
    event LogSubscriptionPriceChanged(address indexed feed, uint256 newSubscriptionPrice);

    /// @notice emitted when feed ipfsCID is changed
    /// @param feed feed address
    /// @param ipfsCID new ipfsCID
    event LogCIDChanged(address indexed feed, string ipfsCID);

    /// @notice emitted when feed frequency is changed
    /// @param feed feed address
    /// @param frequency new frequency
    /// @param pricePerSecondScaled new price per second scaled
    event LogFrequencyChanged(address indexed feed, uint256 frequency, uint256 pricePerSecondScaled);

    /// @notice emitted when feed minSignaturesThreshold is changed
    /// @param feed feed address
    /// @param minSignaturesThreshold new minSignaturesThreshold
    /// @param pricePerSecondScaled new price per second scaled
    event LogMinSignaturesThresholdChanged(address indexed feed, uint256 minSignaturesThreshold, uint256 pricePerSecondScaled);

     /// @notice emitted when feed config is changed
    /// @param feed feed address
    /// @param frequency new frequency
    /// @param minSignaturesThreshold new minSignaturesThreshold
    /// @param pricePerSecondScaled new price per second scaled
    /// @param ipfsCID new ipfsCID
    event LogFeedConfigChanged(
        address indexed feed, 
        uint256 frequency, 
        uint256 minSignaturesThreshold, 
        uint256 pricePerSecondScaled, 
        string ipfsCID
    );
}
