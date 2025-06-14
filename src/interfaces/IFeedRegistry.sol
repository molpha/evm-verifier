// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title IFeedRegistry - Feed registration and lookup
/// @notice Registry of active feeds on the Molpha protocol
interface IFeedRegistry {
    /// @notice Create a new feed
    /// @param metadataHash Hash of the feed metadata stored off-chain (IPFS/Arweave)
    /// @return feedId The unique identifier of the feed
    function createFeed(bytes32 metadataHash) external returns (uint256 feedId);

    /// @notice Returns the on-chain address of a registered feed
    /// @param feedId The feed identifier
    /// @return feedAddress The address of the IFeed implementation
    function getFeed(uint256 feedId) external view returns (address feedAddress);
}
