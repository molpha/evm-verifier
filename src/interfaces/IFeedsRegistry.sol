// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {IFeedsFactory} from "./IFeedsFactory.sol";
import {IFeedsRegistryEvents} from "./IFeedsRegistryEvents.sol";
import {IFeedsRegistryErrors} from "./IFeedsRegistryErrors.sol";

/// @title IFeedsRegistry - Feed registration and lookup
/// @notice Registry of active feeds on the Molpha protocol
interface IFeedsRegistry is IFeedsRegistryEvents, IFeedsRegistryErrors {
    /// @notice Create a new feed
    /// @param metadataHash Hash of the feed metadata stored off-chain (IPFS/Arweave)
    /// @param minSignaturesThreshold The minimum number of signatures required to verify an answer
    /// @return feed The address of the feed
    function createFeed(bytes32 metadataHash, uint256 minSignaturesThreshold) external returns (address feed);

    /// @notice Check if a feed is registered
    /// @param feed The feed address
    /// @return isFeed True if the feed is registered
    function isFeed(address feed) external view returns (bool isFeed);

    /// @notice Get the factory address
    /// @return factory The address of the factory
    function getFeedsFactory() external view returns (IFeedsFactory factory);
}
