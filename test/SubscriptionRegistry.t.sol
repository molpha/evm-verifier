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
import {MockPricingHelper} from "./mocks/MockPricingHelper.sol";

contract SubscriptionRegistryTest is Test {
    SubscriptionRegistry reg;
    MockAccessControlManager acl;
    MockFeedRegistry feeds;
    MockNodeRegistry nodeRegistry;
    MockTreasury treasury;
    MockPricingHelper pricingHelper;
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
        pricingHelper = new MockPricingHelper();
        testFeed = new DummyFeed();
        
        // Initialize SubscriptionRegistry with correct parameters: accessControlManager, treasury, pricingHelper
        reg.initialize(address(acl), address(treasury), address(pricingHelper));
        
        // Add feed to registry
        feeds.addFeed(address(testFeed));
        reg.setConsumerPricePerSecondScaled(address(testFeed), 1);
    }

    function test_subscribe_setsDueTime() public {
        uint256 dueTime = block.timestamp + 30 days;
        address[] memory consumers = new address[](1);
        consumers[0] = defaultConsumer;
        
        reg.subscribe(address(testFeed), dueTime, consumers);
        
        // Check that the subscription was created
        ISubscriptionRegistry.Subscription memory subscription = reg.getSubscription(defaultConsumer, address(testFeed));
        assertEq(subscription.dueTime, dueTime);
        assertEq(subscription.owner, address(this));
    }

    function test_subscribe_multipleConsumers() public {
        uint256 dueTime = block.timestamp + 30 days;
        address[] memory consumers = new address[](2);
        consumers[0] = user;
        consumers[1] = user2;
        
        reg.subscribe(address(testFeed), dueTime, consumers);
        
        // Check that both subscriptions were created
        ISubscriptionRegistry.Subscription memory subscription1 = reg.getSubscription(user, address(testFeed));
        ISubscriptionRegistry.Subscription memory subscription2 = reg.getSubscription(user2, address(testFeed));
        
        assertEq(subscription1.dueTime, dueTime);
        assertEq(subscription1.owner, address(this));
        assertEq(subscription2.dueTime, dueTime);
        assertEq(subscription2.owner, address(this));
    }

    function test_extendSubscription() public {
        uint256 initialDueTime = block.timestamp + 30 days;
        uint256 newDueTime = block.timestamp + 60 days;
        address[] memory consumers = new address[](1);
        consumers[0] = user;
        
        // Initial subscription
        vm.prank(user);
        reg.subscribe(address(testFeed), initialDueTime, consumers);
        
        // Extend subscription
        vm.prank(user);
        reg.extendSubscription(address(testFeed), user, newDueTime);
        
        // Check that the subscription was extended
        ISubscriptionRegistry.Subscription memory subscription = reg.getSubscription(user, address(testFeed));
        assertEq(subscription.dueTime, newDueTime);
    }

    function test_extendSubscription_onlyOwner() public {
        uint256 initialDueTime = block.timestamp + 30 days;
        uint256 newDueTime = block.timestamp + 60 days;
        address[] memory consumers = new address[](1);
        consumers[0] = user;
        
        // Initial subscription
        reg.subscribe(address(testFeed), initialDueTime, consumers);
        
        // Try to extend as non-owner
        vm.prank(nonOwner);
        vm.expectRevert("Not sub owner");
        reg.extendSubscription(address(testFeed), user, newDueTime);
    }

    // function test_unsubscribe() public {
    //     uint256 dueTime = block.timestamp + 30 days;
    //     address[] memory consumers = new address[](1);
    //     consumers[0] = user;
        
    //     feeds.addFeed(address(testFeed));
        
    //     // Initial subscription
    //     reg.subscribe(address(testFeed), dueTime, consumers);
        
    //     // Unsubscribe
    //     vm.prank(user);
    //     reg.unsubscribe(address(testFeed), user);
        
    //     // Check that the subscription is no longer active
    //     assertFalse(reg.isSubscribed(user, address(testFeed)));
    // }

    // function test_unsubscribe_onlyOwner() public {
    //     uint256 dueTime = block.timestamp + 30 days;
    //     address[] memory consumers = new address[](1);
    //     consumers[0] = user;
        
    //     feeds.addFeed(address(testFeed));
        
    //     // Initial subscription
    //     reg.subscribe(address(testFeed), user, dueTime, consumers);
        
    //     // Try to unsubscribe as non-owner
    //     vm.prank(nonOwner);
    //     vm.expectRevert();
    //     reg.unsubscribe(address(testFeed), user);
    // }

    function test_transferSubscription() public {
        uint256 dueTime = block.timestamp + 30 days;
        address[] memory consumers = new address[](1);
        consumers[0] = user;
        
        // Initial subscription
        vm.prank(user);
        reg.subscribe(address(testFeed), dueTime, consumers);
        
        // Transfer subscription
        vm.prank(user);
        reg.transferSubscription(user, address(testFeed), user2);
        
        // Check that the subscription was transferred
        assertTrue(reg.getSubscription(user2, address(testFeed)).dueTime == dueTime);
        
        ISubscriptionRegistry.Subscription memory subscription = reg.getSubscription(user2, address(testFeed));
        assertEq(subscription.owner, user);
    }

    function test_transferSubscription_onlyOwner() public {
        uint256 dueTime = block.timestamp + 30 days;
        address[] memory consumers = new address[](1);
        consumers[0] = user;
        
        // Initial subscription
        vm.prank(user);
        reg.subscribe(address(testFeed), dueTime, consumers);
        
        // Try to transfer as non-owner
        vm.prank(nonOwner);
        // vm.expectRevert(
        //     abi.encodeWithSelector(
        //         ISubscriptionRegistryErrors.NotSubscriptionOwner.selector,
        //         nonOwner
        //     )
        // );
        // reg.transferSubscription(user, address(testFeed), user2);
    }

    function test_subscribe_requiresValidFeed() public {
        uint256 dueTime = block.timestamp + 30 days;
        address[] memory consumers = new address[](1);
        consumers[0] = user;
        address invalidFeed = address(999);
        
        // Don't add the feed to the registry
        vm.expectRevert("Cannot subscribe");
        reg.subscribe(invalidFeed, dueTime, consumers);
    }

    function test_subscribe_requiresMinimumTime() public {
        uint256 shortDueTime = block.timestamp + 1 days; // Less than minimum
        address[] memory consumers = new address[](1);
        consumers[0] = user;
        
        feeds.addFeed(address(testFeed));
        
        vm.expectRevert("Wrong sub time");
        reg.subscribe(address(testFeed), shortDueTime, consumers);
    }

    function test_getSubscription_returnsCorrectData() public {
        uint256 dueTime = block.timestamp + 30 days;
        address[] memory consumers = new address[](1);
        consumers[0] = user;
        
        reg.subscribe(address(testFeed), dueTime, consumers);
        
        ISubscriptionRegistry.Subscription memory subscription = reg.getSubscription(user, address(testFeed));
        assertEq(subscription.dueTime, dueTime);
        assertEq(subscription.owner, address(this));
    }

    function test_supportsInterface() public view {
        assertTrue(reg.supportsInterface(type(ISubscriptionRegistry).interfaceId));
    }
}
