// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFeedRegistry} from "../../src/interfaces/IFeedRegistry.sol";
import {IFeedRegistryStructs} from "../../src/interfaces/IFeedRegistryStructs.sol";
import {IFeedRegistryEvents} from "../../src/interfaces/IFeedRegistryEvents.sol";

// Minimal interface for IFeedFactory since it was deleted but still referenced
interface IFeedFactory {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

contract MockFeedFactory is IFeedFactory {
    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return interfaceId == type(IFeedFactory).interfaceId;
    }
}

contract MockFeedRegistry is IFeedRegistry {
    mapping(address => bool) public feeds;
    mapping(address => IFeedRegistryStructs.FeedConfig) public feedConfigs;
    IFeedFactory public mockFeedFactory;

    constructor() {
        mockFeedFactory = new MockFeedFactory();
    }

    function createFeed(
        IFeedRegistryStructs.FeedType feedType,
        uint256 frequency,
        uint256 minSignaturesThreshold,
        string memory ipfsCID
    ) external override {
        address feed = address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender)))));
        feeds[feed] = true;
        feedConfigs[feed] = IFeedRegistryStructs.FeedConfig({
            feedType: feedType,
            owner: msg.sender,
            ipfsCID: ipfsCID,
            minSignaturesThreshold: minSignaturesThreshold,
            frequency: frequency,
            pricePerSecondScaled: 1000
        });
        
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

    function isFeed(address addr) external view returns (bool) {
        return feeds[addr];
    }

    function getFeedConfig(address feed) external view returns (IFeedRegistryStructs.FeedConfig memory) {
        return feedConfigs[feed];
    }

    function getFeedPrice(address feed) external view returns (uint256) {
        return feedConfigs[feed].pricePerSecondScaled;
    }

    function addFeed(address feed) external {
        feeds[feed] = true;
    }

    function setMockFeedFactory(address factory) external {
        mockFeedFactory = IFeedFactory(factory);
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IFeedRegistry).interfaceId ||
               interfaceId == 0x01ffc9a7; // ERC165 interface ID
    }
}
