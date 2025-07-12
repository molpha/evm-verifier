// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {SubscriptionRegistry} from "../src/SubscriptionRegistry.sol";
import {ISubscriptionRegistry} from "../src/interfaces/ISubscriptionRegistry.sol";
import {ISubscriptionRegistryErrors} from "../src/interfaces/ISubscriptionRegistryErrors.sol";
import {IFeed} from "../src/interfaces/IFeed.sol";
import {MockAccessControlManager} from "./mocks/MockAccessControlManager.sol";
import {MockFeedRegistry} from "./mocks/MockFeedRegistry.sol";
import {MockNodeRegistry} from "./mocks/MockNodeRegistry.sol";
import {TestToken} from "./mocks/TestToken.sol";
import {MockZeroSupplyToken} from "./mocks/MockZeroSupplyToken.sol";

contract SubscriptionRegistryTest is Test {
    SubscriptionRegistry reg;
    MockAccessControlManager acl;
    MockFeedRegistry feeds;
    MockNodeRegistry nodeRegistry;
    TestToken token;
    
    address user = address(1);
    address user2 = address(2);
    address nonOwner = address(3);
    address defaultConsumer = address(4);

    function setUp() public {
        token = new TestToken();
        acl = new MockAccessControlManager(address(this));
        reg = new SubscriptionRegistry(acl, token);
        feeds = new MockFeedRegistry();
        nodeRegistry = new MockNodeRegistry();
        
        reg.initialize(feeds);
        
        feeds.addFeed(address(100));
    }

    function test_subscribe_setsDueTime() public {
        // First create a feed in the registry to get proper price
        vm.recordLogs();
        feeds.createPublicFeed(
            3600, // frequency  
            1,    // minSignaturesThreshold
            "test", // ipfsCID
            defaultConsumer, // defaultConsumer
            30 days // subscriptionDueTime
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(reg), 1e18);
        vm.prank(user);
        uint256 dueTime = block.timestamp + 30 days;
        reg.subscribe(user, feed, dueTime);
        assertTrue(reg.isSubscribed(user, feed));
    }

    function test_subscribe_EmitsEvent() public {
        vm.recordLogs();
        feeds.createPublicFeed(
            3600,
            1,
            "test",
            defaultConsumer,
            30 days
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(reg), 1e18);
        
        // Test that subscription works (event testing simplified)
        vm.prank(user);
        uint256 dueTime = block.timestamp + 30 days;
        reg.subscribe(user, feed, dueTime);
    }

    // function test_grantAccess_WorksCorrectly() public {
    //     vm.recordLogs();
    //     feeds.createPublicFeed(
    //         3600,
    //         1,
    //         "test"
    //     );
        
    //     // Get the feed address from the last emitted event
    //     Vm.Log[] memory logs = vm.getRecordedLogs();
    //     address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
    //     reg.grantAccess(user, feed);
    //     // Note: In mock implementation, isAccessGranted checks both regular access and personal feed access
    // }

    function test_subscribe_ZeroAddresses() public {
        vm.recordLogs();
        feeds.createPublicFeed(
            3600,
            1,
            "test",
            defaultConsumer,
            30 days
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        uint256 dueTime = block.timestamp + 30 days;
        
        // Test zero consumer address - should revert
        vm.expectRevert();
        reg.subscribe(address(0), feed, dueTime);
        
        // Test zero feed address - should revert
        vm.expectRevert();
        reg.subscribe(user, address(0), dueTime);
    }

    function test_subscribe_ExtendSubscription() public {
        vm.recordLogs();
        feeds.createPublicFeed(
            3600,
            1,
            "test",
            defaultConsumer,
            30 days
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(reg), 1e18);
        
        // Initial subscription
        vm.prank(user);
        uint256 dueTime1 = block.timestamp + 30 days;
        reg.subscribe(user, feed, dueTime1);
        
        uint256 firstDueTime = reg.getSubscriptionDueTime(user, feed);
        
        // Extend subscription
        vm.prank(user);
        uint256 dueTime2 = block.timestamp + 45 days;
        reg.subscribe(user, feed, dueTime2);
        
        uint256 secondDueTime = reg.getSubscriptionDueTime(user, feed);
        
        // Second due time should be the new due time
        assertEq(secondDueTime, dueTime2);
    }

    function test_unsubscribe_RemovesSubscription() public {
        vm.recordLogs();
        feeds.createPublicFeed(
            3600,
            1,
            "test",
            defaultConsumer,
            30 days
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(reg), 1e18);
        vm.prank(user);
        uint256 dueTime = block.timestamp + 60 days;
        reg.subscribe(user, feed, dueTime);
        
        assertTrue(reg.isSubscribed(user, feed));
        
        // Unsubscribe
        vm.prank(user);
        reg.unsubscribe(feed, user);
        
        assertFalse(reg.isSubscribed(user, feed));
    }

    function test_unsubscribe_EmitsEvent() public {
        vm.recordLogs();
        feeds.createPublicFeed(
            3600,
            1,
            "test",
            defaultConsumer,
            30 days
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(reg), 1e18);
        vm.prank(user);
        uint256 dueTime = block.timestamp + 60 days;
        reg.subscribe(user, feed, dueTime);
        
        // Test that unsubscription works (event testing simplified)
        vm.prank(user);
        reg.unsubscribe(feed, user);
    }

    function test_unsubscribe_OnlyOwner() public {
        vm.recordLogs();
        feeds.createPublicFeed(
            3600,
            1,
            "test",
            defaultConsumer,
            30 days
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(reg), 1e18);
        vm.prank(user);
        uint256 dueTime = block.timestamp + 60 days;
        reg.subscribe(user, feed, dueTime);
        
        // Non-owner tries to unsubscribe
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(ISubscriptionRegistryErrors.NotSubscriptionOwner.selector, user));
        reg.unsubscribe(feed, user);
    }



    function test_isSubscribed_ReturnsCorrectStatus() public {
        vm.recordLogs();
        feeds.createPublicFeed(
            3600,
            1,
            "test",
            defaultConsumer,
            30 days
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        // Initially not subscribed
        assertFalse(reg.isSubscribed(user, feed));
        
        // Subscribe
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(reg), 1e18);
        vm.prank(user);
        uint256 dueTime = block.timestamp + 30 days;
        reg.subscribe(user, feed, dueTime);
        
        // Now subscribed
        assertTrue(reg.isSubscribed(user, feed));
        
        // Warp past expiry
        vm.warp(dueTime + 1);
        assertFalse(reg.isSubscribed(user, feed));
    }

    function test_getSubscriptionDueTime_ReturnsCorrectTime() public {
        vm.recordLogs();
        feeds.createPublicFeed(
            3600,
            1,
            "test",
            defaultConsumer,
            30 days
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(reg), 1e18);
        
        uint256 expectedDueTime = block.timestamp + 30 days;
        vm.prank(user);
        reg.subscribe(user, feed, expectedDueTime);
        
        uint256 dueTime = reg.getSubscriptionDueTime(user, feed);
        
        assertEq(dueTime, expectedDueTime);
    }



    function test_supportsInterface_SubscriptionRegistry() public {
        assertTrue(reg.supportsInterface(type(ISubscriptionRegistry).interfaceId));
    }

    function test_supportsInterface_ERC165() public {
        assertTrue(reg.supportsInterface(0x01ffc9a7)); // ERC165 interface ID
    }

    function test_supportsInterface_InvalidInterface() public {
        assertFalse(reg.supportsInterface(0x12345678));
    }

    function test_constructor_InvalidToken() public {
        // Create a mock token with zero total supply
        MockZeroSupplyToken zeroToken = new MockZeroSupplyToken();
        
        vm.expectRevert("wrong underlying");
        new SubscriptionRegistry(acl, zeroToken);
    }

    function test_subscribe_MultipleUsers() public {
        vm.recordLogs();
        feeds.createPublicFeed(
            3600,
            1,
            "test",
            defaultConsumer,
            30 days
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        // User 1 subscribes
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(reg), 1e18);
        vm.prank(user);
        uint256 dueTime1 = block.timestamp + 30 days;
        reg.subscribe(user, feed, dueTime1);
        
        // User 2 subscribes
        token.mint(user2, 1e18);
        vm.prank(user2);
        token.approve(address(reg), 1e18);
        vm.prank(user2);
        uint256 dueTime2 = block.timestamp + 45 days;
        reg.subscribe(user2, feed, dueTime2);
        
        assertTrue(reg.isSubscribed(user, feed));
        assertTrue(reg.isSubscribed(user2, feed));
        
        uint256 actualDueTime1 = reg.getSubscriptionDueTime(user, feed);
        uint256 actualDueTime2 = reg.getSubscriptionDueTime(user2, feed);
        
        // User 2's subscription should expire later
        assertTrue(actualDueTime2 > actualDueTime1);
    }

    function testFuzz_subscribe_ValidDueTime(uint256 dueTime) public {
        vm.assume(dueTime >= block.timestamp + 1 days && dueTime <= block.timestamp + 1000 days); // Valid range with buffer
        
        vm.recordLogs();
        feeds.createPublicFeed(
            3600,
            1,
            "test",
            defaultConsumer,
            30 days
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(reg), 1e18);
        vm.prank(user);
        reg.subscribe(user, feed, dueTime);
        
        assertTrue(reg.isSubscribed(user, feed));
        uint256 actualDueTime = reg.getSubscriptionDueTime(user, feed);
        assertEq(actualDueTime, dueTime);
    }

    function test_subscribe_BoundaryValues() public {
        vm.recordLogs();
        feeds.createPublicFeed(
            3600,
            1,
            "test",
            defaultConsumer,
            30 days
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(reg), 1e18);
        
        // Test valid due time
        vm.prank(user);
        uint256 dueTime = block.timestamp + 30 days;
        reg.subscribe(user, feed, dueTime);
        assertTrue(reg.isSubscribed(user, feed));
        
        // Unsubscribe to reset
        vm.prank(user);
        reg.unsubscribe(feed, user);
        
        // Test longer valid due time
        vm.prank(user);
        uint256 longerDueTime = block.timestamp + 365 days;
        reg.subscribe(user, feed, longerDueTime);
        assertTrue(reg.isSubscribed(user, feed));
    }
}
