// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Feed, IFeed} from "../src/Feed.sol";
import {INodesAggregator} from "../src/interfaces/INodesAggregator.sol";
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

    function setUp() public {
        aggregator = new MockNodesAggregator();
        subRegistry = new MockSubscriptionsRegistry();
        acl = new MockAccessControlManager(address(this));
        feed = new Feed(acl, aggregator, subRegistry);
        feed.minSignaturesThreshold(); // read to silence warnings
    }

    function test_publishAnswer_StoresData() public {
        IFeed.Answer memory ans = IFeed.Answer("data", uint64(block.timestamp));
        feed.publishAnswer(ans, INodesAggregator.SchnorrSignature(bytes32(1), address(1), new uint256[](1)));
        (bytes memory value, uint256 ts) = feed.getLatest();
        assertEq(value, "data");
        assertEq(ts, ans.timestamp);
        assertEq(aggregator.lastMessage(), keccak256(abi.encodePacked(address(feed), ans.value, ans.timestamp)).toEthSignedMessageHash());
    }
}
