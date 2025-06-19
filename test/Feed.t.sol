// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {Feed} from "../src/Feed.sol";
import {IFeed, IFeedStructs} from "../src/interfaces/IFeed.sol";
import {INodesAggregator, INodesAggregatorStructs} from "../src/interfaces/INodesAggregator.sol";
import {MessageHashUtils} from "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {MockAccessControlManager} from "./mocks/MockAccessControlManager.sol";
import {MockNodesAggregator} from "./mocks/MockNodesAggregator.sol";
import {MockSubscriptionsRegistry} from "./mocks/MockSubscriptionsRegistry.sol";

using MessageHashUtils for bytes32;

contract FeedTest is Test {
    Feed feed;
    MockNodesAggregator aggregator;
    MockSubscriptionsRegistry subRegistry;
    MockAccessControlManager acl;

    address consumer = address(1);

    function setUp() public {
        aggregator = new MockNodesAggregator();
        subRegistry = new MockSubscriptionsRegistry();
        acl = new MockAccessControlManager(address(this));
        feed = new Feed(acl, aggregator, subRegistry);
        feed.getMinSignaturesThreshold(); // read to silence warnings
    }

    function test_publishAnswer_StoresData() public {
        // Subscribe the test contract first
        subRegistry.subscribe(address(this), address(feed), 100);
        
        IFeedStructs.Answer memory ans = IFeedStructs.Answer("data", uint64(block.timestamp));
        
        // Set the expected message in the mock
        bytes32 expectedMessage = keccak256(abi.encodePacked(address(feed), ans.value, ans.timestamp)).toEthSignedMessageHash();
        aggregator.setLastMessage(expectedMessage);
        
        feed.publishAnswer(ans, INodesAggregatorStructs.SchnorrSignature(bytes32(uint256(1)), address(1), new uint256[](1)));
        
        (bytes memory value, uint256 ts) = feed.getLatest();
        
        assertEq(value, "data");
        assertEq(ts, ans.timestamp);
        assertEq(aggregator.lastMessage(), expectedMessage);
    }
}
