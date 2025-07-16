// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {SubscriptionRegistry} from "../src/SubscriptionRegistry.sol";
import {ISubscriptionRegistry} from "../src/interfaces/ISubscriptionRegistry.sol";
import {IFeedRegistry} from "../src/interfaces/IFeedRegistry.sol";
import {IFeed} from "../src/interfaces/IFeed.sol";
import {MockAccessControlManager} from "./mocks/MockAccessControlManager.sol";
import {MockFeedRegistry} from "./mocks/MockFeedRegistry.sol";
import {MockNodeRegistry} from "./mocks/MockNodeRegistry.sol";
import {MockTreasury} from "./mocks/MockTreasury.sol";
import {DummyFeed} from "./mocks/DummyFeed.sol";
import {TestToken} from "./mocks/TestToken.sol";

contract SubscriptionRegistryTest is Test {
    SubscriptionRegistry reg;
    MockAccessControlManager acl;
    MockFeedRegistry feeds;
    MockNodeRegistry nodeRegistry;
    MockTreasury treasury;
    TestToken token;
    DummyFeed testFeed;
    
    address user = address(1);
    address user2 = address(2);
    address nonOwner = address(3);
    address defaultConsumer = address(4);

    function setUp() public {
        token = new TestToken();
        acl = new MockAccessControlManager(address(this));
        reg = new SubscriptionRegistry();
        feeds = new MockFeedRegistry();
        nodeRegistry = new MockNodeRegistry();
        treasury = new MockTreasury();
        testFeed = new DummyFeed();
        
        reg.initialize(address(acl), address(feeds), address(treasury));
        
        feeds.addFeed(address(address(testFeed)));
    }

    function test_subscribe_setsDueTime() public {
        uint256 dueTime = block.timestamp + 30 days;
        address[] memory consumers = new address[](1);
        consumers[0] = defaultConsumer;
        
        // Mock the feed registry to return that this is a valid feed
        feeds.addFeed(address(address(testFeed)));
        
        reg.subscribe(address(address(testFeed)), user, dueTime, consumers);
        
        // Check that the subscription was created
        ISubscriptionRegistry.Subscription memory subscription = reg.getSubscription(defaultConsumer, address(address(testFeed)));
        assertEq(subscription.dueTime, dueTime);
        assertEq(subscription.owner, user);
    }

    function test_subscribe_multipleConsumers() public {
        uint256 dueTime = block.timestamp + 30 days;
        address[] memory consumers = new address[](2);
        consumers[0] = user;
        consumers[1] = user2;
        
        feeds.addFeed(address(testFeed));
        
        reg.subscribe(address(testFeed), user, dueTime, consumers);
        
        // Check that both subscriptions were created
        ISubscriptionRegistry.Subscription memory subscription1 = reg.getSubscription(user, address(testFeed));
        ISubscriptionRegistry.Subscription memory subscription2 = reg.getSubscription(user2, address(testFeed));
        
        assertEq(subscription1.dueTime, dueTime);
        assertEq(subscription1.owner, user);
        assertEq(subscription2.dueTime, dueTime);
        assertEq(subscription2.owner, user);
    }

    function test_isSubscribed_returnsTrue() public {
        uint256 dueTime = block.timestamp + 30 days;
        address[] memory consumers = new address[](1);
        consumers[0] = user;
        
        feeds.addFeed(address(testFeed));
        
        reg.subscribe(address(testFeed), user, dueTime, consumers);
        
        assertTrue(reg.isSubscribed(user, address(testFeed)));
    }

    function test_isSubscribed_returnsFalse() public {
        feeds.addFeed(address(testFeed));
        
        assertFalse(reg.isSubscribed(user, address(testFeed)));
    }

    function test_isSubscribed_returnsFalseForExpired() public {
        uint256 dueTime = block.timestamp + 30 days + 1; // Minimum subscription time + 1 second
        address[] memory consumers = new address[](1);
        consumers[0] = user;
        
        feeds.addFeed(address(testFeed));
        
        reg.subscribe(address(testFeed), user, dueTime, consumers);
        
        // Move time forward past expiration
        vm.warp(dueTime + 1);
        
        assertFalse(reg.isSubscribed(user, address(testFeed)));
    }

    function test_extendSubscription() public {
        uint256 initialDueTime = block.timestamp + 30 days;
        uint256 newDueTime = block.timestamp + 60 days;
        address[] memory consumers = new address[](1);
        consumers[0] = user;
        
        feeds.addFeed(address(testFeed));
        
        // Initial subscription
        reg.subscribe(address(testFeed), user, initialDueTime, consumers);
        
        // Extend subscription
        vm.prank(user);
        reg.extendSubscription(user, address(testFeed), newDueTime);
        
        // Check that the subscription was extended
        ISubscriptionRegistry.Subscription memory subscription = reg.getSubscription(user, address(testFeed));
        assertEq(subscription.dueTime, newDueTime);
    }

    function test_extendSubscription_onlyOwner() public {
        uint256 initialDueTime = block.timestamp + 30 days;
        uint256 newDueTime = block.timestamp + 60 days;
        address[] memory consumers = new address[](1);
        consumers[0] = user;
        
        feeds.addFeed(address(testFeed));
        
        // Initial subscription
        reg.subscribe(address(testFeed), user, initialDueTime, consumers);
        
        // Try to extend as non-owner
        vm.prank(nonOwner);
        vm.expectRevert();
        reg.extendSubscription(user, address(testFeed), newDueTime);
    }

    function test_unsubscribe() public {
        uint256 dueTime = block.timestamp + 30 days;
        address[] memory consumers = new address[](1);
        consumers[0] = user;
        
        feeds.addFeed(address(testFeed));
        
        // Initial subscription
        reg.subscribe(address(testFeed), user, dueTime, consumers);
        
        // Unsubscribe
        vm.prank(user);
        reg.unsubscribe(address(testFeed), user);
        
        // Check that the subscription is no longer active
        assertFalse(reg.isSubscribed(user, address(testFeed)));
    }

    function test_unsubscribe_onlyOwner() public {
        uint256 dueTime = block.timestamp + 30 days;
        address[] memory consumers = new address[](1);
        consumers[0] = user;
        
        feeds.addFeed(address(testFeed));
        
        // Initial subscription
        reg.subscribe(address(testFeed), user, dueTime, consumers);
        
        // Try to unsubscribe as non-owner
        vm.prank(nonOwner);
        vm.expectRevert();
        reg.unsubscribe(address(testFeed), user);
    }

    function test_transferSubscription() public {
        uint256 dueTime = block.timestamp + 30 days;
        address[] memory consumers = new address[](1);
        consumers[0] = user;
        
        feeds.addFeed(address(testFeed));
        
        // Initial subscription
        reg.subscribe(address(testFeed), user, dueTime, consumers);
        
        // Transfer subscription
        vm.prank(user);
        reg.transferSubscription(user, address(testFeed), user2);
        
        // Check that the subscription was transferred
        assertFalse(reg.isSubscribed(user, address(testFeed)));
        assertTrue(reg.isSubscribed(user2, address(testFeed)));
        
        ISubscriptionRegistry.Subscription memory subscription = reg.getSubscription(user2, address(testFeed));
        assertEq(subscription.owner, user);
    }

    function test_transferSubscription_onlyOwner() public {
        uint256 dueTime = block.timestamp + 30 days;
        address[] memory consumers = new address[](1);
        consumers[0] = user;
        
        feeds.addFeed(address(testFeed));
        
        // Initial subscription
        reg.subscribe(address(testFeed), user, dueTime, consumers);
        
        // Try to transfer as non-owner
        vm.prank(nonOwner);
        vm.expectRevert();
        reg.transferSubscription(user, address(testFeed), user2);
    }

    function test_subscribe_requiresValidFeed() public {
        uint256 dueTime = block.timestamp + 30 days;
        address[] memory consumers = new address[](1);
        consumers[0] = user;
        address invalidFeed = address(999);
        
        // Don't add the feed to the registry
        vm.expectRevert();
        reg.subscribe(invalidFeed, user, dueTime, consumers);
    }

    function test_subscribe_requiresMinimumTime() public {
        uint256 shortDueTime = block.timestamp + 1 days; // Less than minimum
        address[] memory consumers = new address[](1);
        consumers[0] = user;
        
        feeds.addFeed(address(testFeed));
        
        vm.expectRevert();
        reg.subscribe(address(testFeed), user, shortDueTime, consumers);
    }

    function test_getSubscription_returnsCorrectData() public {
        uint256 dueTime = block.timestamp + 30 days;
        address[] memory consumers = new address[](1);
        consumers[0] = user;
        
        feeds.addFeed(address(testFeed));
        
        reg.subscribe(address(testFeed), user, dueTime, consumers);
        
        ISubscriptionRegistry.Subscription memory subscription = reg.getSubscription(user, address(testFeed));
        assertEq(subscription.dueTime, dueTime);
        assertEq(subscription.owner, user);
    }

    function test_supportsInterface() public {
        assertTrue(reg.supportsInterface(type(ISubscriptionRegistry).interfaceId));
    }
}
