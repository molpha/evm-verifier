// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {FeedsRegistry} from "../src/FeedsRegistry.sol";
import {MockAccessControlManager} from "./mocks/MockAccessControlManager.sol";
import {MockFeedsFactory} from "./mocks/MockFeedsFactory.sol";
import {MockSubscriptionsRegistry} from "./mocks/MockSubscriptionsRegistry.sol";
import {DummyFeed} from "./mocks/DummyFeed.sol";

contract FeedsRegistryTest is Test {
    FeedsRegistry registry;
    MockFeedsFactory factory;
    MockSubscriptionsRegistry subRegistry;
    MockAccessControlManager acl;

    address manager;

    function setUp() public {
        manager = address(this); // Use the test contract as manager
        acl = new MockAccessControlManager(manager);
        registry = new FeedsRegistry(acl);
        factory = new MockFeedsFactory();
        subRegistry = new MockSubscriptionsRegistry();
        registry.initialize(factory, subRegistry);
    }

    function test_createFeed_AddsFeed() public {
        factory.setAggregatorImpl(address(new DummyFeed()));
        address feed = registry.createFeed(bytes32(0), 0);
        assertTrue(registry.isFeed(feed));
    }

    // function test_setSubscriptionPrice_Works() public {
    //     factory.setAggregatorImpl(address(new DummyFeed()));
    //     address feed = registry.createFeed(bytes32(0), 0, 1, 0);

    //     registry.setSubscriptionPrice(feed, 10);
    //     assertEq(subRegistry.price(), 10);
    // }
}
