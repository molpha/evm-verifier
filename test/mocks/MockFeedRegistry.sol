// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IFeedRegistry} from "../../src/interfaces/IFeedRegistry.sol";
import {IFeed} from "../../src/interfaces/IFeed.sol";
import {IDataSourceRegistry} from "../../src/interfaces/IDataSourceRegistry.sol";

contract MockFeedRegistry is IFeedRegistry {
    mapping(address => bool) public feeds;
    address[] public feedList;

    function initialize(address accessControlManager, address subscriptionRegistry, address dataSourceRegistry) external {
        // Mock implementation - no actual initialization needed
    }

    function createFeed(CreateFeedParams calldata params, CreateDataSourceParams calldata /*dataSourceParams*/) external {
        // Mock implementation - create a dummy feed address
        address feed = address(uint160(uint256(keccak256(abi.encodePacked(
            params.feedType,
            params.frequency,
            params.minSignaturesThreshold,
            params.ipfsCID,
            block.timestamp
        )))));
        
        feeds[feed] = true;
        feedList.push(feed);
        
        emit LogFeedCreated(
            feed,
            params.feedType,
            params.frequency,
            params.minSignaturesThreshold,
            params.ipfsCID
        );
    }

    function createFeed(CreateFeedParams calldata params, bytes32 dataSourceId) external {
        // Mock implementation - create a dummy feed address
        address feed = address(uint160(uint256(keccak256(abi.encodePacked(
            params.feedType,
            params.frequency,
            params.minSignaturesThreshold,
            params.ipfsCID,
            dataSourceId
        )))));
        
        feeds[feed] = true;
        feedList.push(feed);
        
        emit LogFeedCreated(
            feed,
            params.feedType,
            params.frequency,
            params.minSignaturesThreshold,
            params.ipfsCID
        );
    }

    function updateFeed(
        address feed, 
        uint256 frequency, 
        uint256 signaturesRequired, 
        string calldata ipfsCID
    ) external {
        // Mock implementation
    }

    function setAccessControlManager(address accessControlManager) external {
        // Mock implementation
    }

    function setSubscriptionRegistry(address subscriptionRegistry) external {
        // Mock implementation
    }

    function isFeed(address feed) external view returns (bool) {
        return feeds[feed];
    }

    // Helper functions for testing
    function addFeed(address feed) external {
        feeds[feed] = true;
        feedList.push(feed);
    }

    function removeFeed(address feed) external {
        feeds[feed] = false;
        // Note: This doesn't remove from feedList for simplicity
    }

    function getFeedCount() external view returns (uint256) {
        return feedList.length;
    }

    function getFeedAtIndex(uint256 index) external view returns (address) {
        return feedList[index];
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IFeedRegistry).interfaceId || interfaceId == 0x01ffc9a7; // ERC165
    }
}
