// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IFeed} from "../../src/interfaces/IFeed.sol";
import {IFeedRegistry} from "../../src/interfaces/IFeedRegistry.sol";
import {DummyFeed} from "./DummyFeed.sol";

contract MockFeedRegistry is IFeedRegistry {
    mapping(address => bool) public feeds;
    mapping(address => string) public feedCIDs;
    mapping(address => uint256) public feedFrequencies;
    mapping(address => uint256) public feedMinSignaturesThresholds;
    mapping(address => uint256) public feedPrices;
    mapping(address => IFeed.FeedType) public feedTypes;
    mapping(address => address) public feedOwners;

    function createPublicFeed(
        uint256 frequency,
        uint256 minSignaturesThreshold,
        string memory ipfsCID,
        address defaultConsumer,
        uint256 subscriptionDueTime
    ) external override {
        DummyFeed feed = new DummyFeed();
        feed.setFeedType(IFeed.FeedType.PUBLIC);
        feed.setOwner(msg.sender);
        
        address feedAddr = address(feed);
        feeds[feedAddr] = true;
        feedCIDs[feedAddr] = ipfsCID;
        feedFrequencies[feedAddr] = frequency;
        feedMinSignaturesThresholds[feedAddr] = minSignaturesThreshold;
        feedPrices[feedAddr] = 1000;
        feedTypes[feedAddr] = IFeed.FeedType.PUBLIC;
        feedOwners[feedAddr] = msg.sender;

        emit LogFeedCreated(feedAddr, IFeed.FeedType.PUBLIC, frequency, minSignaturesThreshold, ipfsCID);
    }

    function createPersonalFeed(
        uint256 frequency,
        uint256 minSignaturesThreshold,
        string memory ipfsCID,
        uint256 subscriptionDueTime
    ) external override {
        DummyFeed feed = new DummyFeed();
        feed.setFeedType(IFeed.FeedType.PERSONAL);
        feed.setOwner(msg.sender);
        
        address feedAddr = address(feed);
        feeds[feedAddr] = true;
        feedCIDs[feedAddr] = ipfsCID;
        feedFrequencies[feedAddr] = frequency;
        feedMinSignaturesThresholds[feedAddr] = minSignaturesThreshold;
        feedPrices[feedAddr] = 1000;
        feedTypes[feedAddr] = IFeed.FeedType.PERSONAL;
        feedOwners[feedAddr] = msg.sender;

        emit LogFeedCreated(feedAddr, IFeed.FeedType.PERSONAL, frequency, minSignaturesThreshold, ipfsCID);
    }

    // Additional helper functions for testing
    function updateFeedConfig(address feed, uint256 frequency, uint256 minSignaturesThreshold, string calldata ipfsCID) external {
        feedFrequencies[feed] = frequency;
        feedMinSignaturesThresholds[feed] = minSignaturesThreshold;
        feedCIDs[feed] = ipfsCID;
    }

    function setFrequency(address feed, uint256 frequency) external {
        feedFrequencies[feed] = frequency;
    }

    function setMinSignaturesThreshold(address feed, uint256 minSignaturesThreshold) external {
        feedMinSignaturesThresholds[feed] = minSignaturesThreshold;
    }

    function setCID(address feed, string calldata ipfsCID) external {
        feedCIDs[feed] = ipfsCID;
    }

    function getFeedCID(address feed) external view returns (string memory) {
        return feedCIDs[feed];
    }

    function getFeedFrequency(address feed) external view returns (uint256) {
        return feedFrequencies[feed];
    }

    function getFeedMinSignaturesThreshold(address feed) external view returns (uint256) {
        return feedMinSignaturesThresholds[feed];
    }

    function getFeedPrice(address feed) external view returns (uint256) {
        return feedPrices[feed];
    }

    function getFeedType(address feed) external view returns (IFeed.FeedType) {
        return feedTypes[feed];
    }

    function getFeedOwner(address feed) external view returns (address) {
        return feedOwners[feed];
    }

    function addFeed(address feed) external {
        feeds[feed] = true;
        feedTypes[feed] = IFeed.FeedType.PUBLIC;
        feedOwners[feed] = msg.sender;
        feedCIDs[feed] = "test";
        feedFrequencies[feed] = 3600;
        feedMinSignaturesThresholds[feed] = 1;
        feedPrices[feed] = 1000;
    }

    function setFeedType(address feed, IFeed.FeedType feedType) external {
        feedTypes[feed] = feedType;
    }

    function setFeedOwner(address feed, address owner) external {
        feedOwners[feed] = owner;
    }

    function setFeedPrice(address feed, uint256 price) external {
        feedPrices[feed] = price;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IFeedRegistry).interfaceId ||
               interfaceId == 0x01ffc9a7; // ERC165 interface ID
    }
}
