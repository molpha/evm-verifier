// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {INodeRegistry, INodeRegistryStructs} from "./INodeRegistry.sol";
import {ISubscriptionRegistry} from "./ISubscriptionRegistry.sol";
import {IFeedStructs} from "./IFeedStructs.sol";
import {IFeedEvents} from "./IFeedEvents.sol";
import {IFeedErrors} from "./IFeedErrors.sol";

/// @title IFeed - Interface for a data feed contract
/// @notice Handles feed metadata, update logic, and on-chain value access
/// @dev Implemented by specific feed contracts
interface IFeed is IFeedStructs, IFeedEvents, IFeedErrors {
    /// @notice Publish an answer
    /// @param answer The answer to publish
    /// @param schnorrData The Schnorr signature data
    function publishAnswer(Answer calldata answer, INodeRegistryStructs.SchnorrSignature calldata schnorrData) external;

    /// @notice Set the minimum number of signatures required to verify an answer
    /// @dev This function is only callable by the feed manager and only for personal feeds
    /// @param minSignaturesThreshold The minimum number of signatures required
    function setMinSignaturesThreshold(uint256 minSignaturesThreshold) external;

    /// @notice Returns the minimum number of signatures required to verify an answer
    /// @return minSignaturesThreshold The minimum number of signatures required
    function getMinSignaturesThreshold() external view returns (uint256 minSignaturesThreshold);

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
    /// @return value The value of the entry
    /// @return timestamp The timestamp of the entry
    function getEntry(uint256 index) external view returns (bytes memory value, uint256 timestamp);
}