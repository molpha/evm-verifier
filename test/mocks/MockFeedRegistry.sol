// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IFeed} from "../../src/interfaces/IFeed.sol";
import {IFeedRegistry} from "../../src/interfaces/IFeedRegistry.sol";
import {IFeedRegistryStructs} from "../../src/interfaces/IFeedRegistryStructs.sol";
contract MockFeedRegistry is IFeedRegistry {
    mapping(address => bool) public feeds;
    mapping(address => IFeedRegistryStructs.FeedConfig) public feedConfigs;
    mapping(address => IFeed.FeedType) public feedTypes;
    mapping(address => address) public feedOwners;

    function createFeed(
        IFeed.FeedType feedType,
        uint256 frequency,
        uint256 minSignaturesThreshold,
        string memory ipfsCID
    ) external override {
        address feed = address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender)))));
        feeds[feed] = true;
        feedConfigs[feed] = IFeedRegistryStructs.FeedConfig({
            ipfsCID: ipfsCID,
            minSignaturesThreshold: minSignaturesThreshold,
            frequency: frequency,
            pricePerSecondScaled: 1000
        });
        feedTypes[feed] = feedType;
        feedOwners[feed] = msg.sender;
        
        emit LogFeedCreated(feed, feedType, frequency, minSignaturesThreshold, ipfsCID);
    }

    function updateFeedConfig(address feed, uint256 frequency, uint256 minSignaturesThreshold, string calldata ipfsCID) external {
        feedConfigs[feed].frequency = frequency;
        feedConfigs[feed].minSignaturesThreshold = minSignaturesThreshold;
        feedConfigs[feed].ipfsCID = ipfsCID;
    }

    function setFrequency(address feed, uint256 frequency) external {
        feedConfigs[feed].frequency = frequency;
    }

    function setMinSignaturesThreshold(address feed, uint256 minSignaturesThreshold) external {
        feedConfigs[feed].minSignaturesThreshold = minSignaturesThreshold;
    }

    function setCID(address feed, string calldata ipfsCID) external {
        feedConfigs[feed].ipfsCID = ipfsCID;
    }

    function isFeed(address addr) external view override returns (bool) {
        return feeds[addr];
    }

    function getFeedConfig(address feed) external view returns (IFeedRegistryStructs.FeedConfig memory) {
        return feedConfigs[feed];
    }

    function getFeedPrice(address feed) external view returns (uint256) {
        return feedConfigs[feed].pricePerSecondScaled;
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
        feedConfigs[feed] = IFeedRegistryStructs.FeedConfig({
            ipfsCID: "test",
            minSignaturesThreshold: 1,
            frequency: 3600,
            pricePerSecondScaled: 1000
        });
    }



    function setFeedType(address feed, IFeed.FeedType feedType) external {
        feedTypes[feed] = feedType;
    }

    function setFeedOwner(address feed, address owner) external {
        feedOwners[feed] = owner;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IFeedRegistry).interfaceId ||
               interfaceId == 0x01ffc9a7; // ERC165 interface ID
    }
}
