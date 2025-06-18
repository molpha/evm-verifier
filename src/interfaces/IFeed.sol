// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {INodesAggregator} from "./INodesAggregator.sol";
import {ISubscriptionsRegistry} from "./ISubscriptionsRegistry.sol";
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
    function publishAnswer(Answer calldata answer, INodesAggregator.SchnorrSignature calldata schnorrData) external;

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

    /// @notice Returns the subscriptions registry
    /// @return subscriptionsRegistry The subscriptions registry
    function getSubscriptionsRegistry() external view returns (ISubscriptionsRegistry subscriptionsRegistry);

    /// @notice Returns the entry at a specific index
    /// @param index The index of the entry
    /// @return value The value of the entry
    /// @return timestamp The timestamp of the entry
    function getEntry(uint256 index) external view returns (bytes memory value, uint256 timestamp);
}
