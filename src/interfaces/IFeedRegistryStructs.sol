// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title IFeedRegistry - Feed registration and lookup
/// @notice Registry of active feeds on the Molpha protocol
interface IFeedRegistryStructs {
    /// TODO: optimize the feed config for gas efficiency
    /// @notice Feed configuration
    /// @param feedType The type of the feed
    /// @param owner The owner of the feed
    /// @param ipfsCID The IPFS CID of the feed metadata
    /// @param minSignaturesThreshold The minimum number of signatures required to verify an answer
    /// @param frequency The frequency of the feed
    /// @param pricePerSecondScaled The price per second scaled
    struct FeedConfig {
        FeedType feedType;
        address owner;
        string  ipfsCID;
        uint256 minSignaturesThreshold;
        uint256 frequency;
        // we keep it precomputed for gas efficiency and update it only when the feed config is updated
        uint256 pricePerSecondScaled; 
    }

    /// @notice Feed type
    /// @param PUBLIC The public feed
    /// @param PERSONAL The personal feed
    enum FeedType {
        PUBLIC,
        PERSONAL
    }
}
