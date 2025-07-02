// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title IFeedRegistryErrors - Errors for the FeedRegistry
/// @notice Errors for the FeedRegistry
interface IFeedRegistryErrors {
    /// @notice thrown when address is not feed
    /// @param addr address
    error NotFeed(address addr);

    /// @notice thrown when feed config is invalid
    error InvalidFeedConfig();

    /// @notice thrown when address is not feed owner
    /// @param addr address
    error NotFeedOwner(address addr);

    /// @notice thrown when frequency is not valid
    /// @param frequency frequency
    error InvalidFrequency(uint256 frequency);

    /// @notice thrown when feed is not personal
    /// @param feed feed address
    error NotPersonalFeed(address feed);

    /// @notice thrown when minSignaturesThreshold is not valid
    /// @param minSignaturesThreshold minSignaturesThreshold
    error InvalidMinSignaturesThreshold(uint256 minSignaturesThreshold);

    /// @notice thrown when ipfsCID is invalid
    /// @param ipfsCID ipfsCID
    error InvalidCID(string ipfsCID);
}