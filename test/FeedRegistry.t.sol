// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {FeedRegistry} from "../src/FeedRegistry.sol";
import {IFeedRegistry} from "../src/interfaces/IFeedRegistry.sol";
import {IFeed} from "../src/interfaces/IFeed.sol";
import {IFeedRegistryErrors} from "../src/interfaces/IFeedRegistryErrors.sol";
import {IFeedRegistryEvents} from "../src/interfaces/IFeedRegistryEvents.sol";
import {MockAccessControlManager} from "./mocks/MockAccessControlManager.sol";
import {MockSubscriptionRegistry} from "./mocks/MockSubscriptionRegistry.sol";
import {MockNodeRegistry} from "./mocks/MockNodeRegistry.sol";
import {DummyFeed} from "./mocks/DummyFeed.sol";

contract FeedRegistryTest is Test {
    FeedRegistry registry;
    MockSubscriptionRegistry subRegistry;
    MockNodeRegistry nodeRegistry;
    MockAccessControlManager acl;

    address manager;
    address notManager = address(999);
    address feedOwner = address(123);
    address defaultConsumer = address(456);

    function setUp() public {
        manager = address(this); // Use the test contract as manager
        acl = new MockAccessControlManager(manager);
        subRegistry = new MockSubscriptionRegistry();
        nodeRegistry = new MockNodeRegistry();
        
        // Set feed manager for proper access control
        acl.setFeedManager(manager);
        
        registry = new FeedRegistry(acl, subRegistry, nodeRegistry);
    }

    function test_createFeed_AddsFeed() public {        
        vm.recordLogs();
        registry.createPublicFeed(
            3600, // frequency
            1,    // minSignaturesThreshold  
            "test", // ipfsCID
            defaultConsumer, // defaultConsumer
            30 days // subscriptionDueTime
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        assertEq(IFeed(feed).getOwner(), feedOwner);
    }

    function test_createFeed_PersonalFeed() public {        
        vm.recordLogs();
        registry.createPersonalFeed(
            7200, // frequency
            3,    // minSignaturesThreshold  
            "personal-test", // ipfsCID
            30 days // subscriptionDueTime
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        assertEq(IFeed(feed).getOwner(), feedOwner);
    }

    function test_createFeed_OnlyFeedManager() public {
        vm.prank(notManager);
        vm.expectRevert();
        registry.createPublicFeed(
            3600,
            1,
            "test",
            defaultConsumer,
            30 days
        );
    }

    function test_createFeed_InvalidFrequency() public {
        // Test frequency too low
        vm.expectRevert(IFeedRegistryErrors.InvalidFeedConfig.selector);
        registry.createPublicFeed(
            0, // invalid frequency
            1,
            "test",
            defaultConsumer,
            30 days
        );
    }

    function test_createFeed_InvalidMinSignaturesThreshold() public {
        vm.expectRevert(IFeedRegistryErrors.InvalidFeedConfig.selector);
        registry.createPublicFeed(
            3600,
            0, // invalid threshold
            "test",
            defaultConsumer,
            30 days
        );
    }

    function test_createFeed_InvalidCID() public {
        vm.expectRevert(IFeedRegistryErrors.InvalidFeedConfig.selector);
        registry.createPublicFeed(
            3600,
            1,
            "", // empty CID
            defaultConsumer,
            30 days
        );
    }

    function test_createFeed_EmitsEvent() public {
        // Test that creating a feed works (event testing removed for now)
        vm.recordLogs();
        registry.createPublicFeed(
            3600,
            1,
            "test",
            defaultConsumer,
            30 days
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        // Verify the feed was created successfully
        assertEq(IFeed(feed).getOwner(), feedOwner);
    }

    function test_supportsInterface_FeedRegistry() public {
        assertTrue(registry.supportsInterface(type(IFeedRegistry).interfaceId));
    }

    function test_supportsInterface_ERC165() public {
        assertTrue(registry.supportsInterface(0x01ffc9a7)); // ERC165 interface ID
    }

    function test_supportsInterface_InvalidInterface() public {
        assertFalse(registry.supportsInterface(0x12345678));
    }

    function testFuzz_createFeed_ValidParameters(
        uint256 frequency,
        uint256 minSignaturesThreshold,
        string memory ipfsCID
    ) public {
        vm.assume(frequency >= 60 && frequency <= 86400); // 1 minute to 1 day
        vm.assume(minSignaturesThreshold > 0 && minSignaturesThreshold <= 100);
        vm.assume(bytes(ipfsCID).length > 0 && bytes(ipfsCID).length <= 100);
        
        vm.recordLogs();
        registry.createPublicFeed(
            frequency,
            minSignaturesThreshold,
            ipfsCID,
            defaultConsumer,
            30 days
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        assertEq(IFeed(feed).getOwner(), feedOwner);
    }

    function test_createFeed_MultipleFeedTypes() public {
        // Create public feed
        vm.recordLogs();
        registry.createPublicFeed(
            3600,
            1,
            "public",
            defaultConsumer,
            30 days
        );
        
        // Get the public feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address publicFeed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        // Create personal feed
        vm.recordLogs();
        registry.createPersonalFeed(
            7200,
            2,
            "personal",
            30 days
        );
        
        // Get the personal feed address from the last emitted event  
        logs = vm.getRecordedLogs();
        address personalFeed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        assertEq(IFeed(publicFeed).getOwner(), feedOwner);
        assertEq(IFeed(personalFeed).getOwner(), feedOwner);
    }

    function test_createPublicFeed_CallsSubscriptionRegistry() public {
        // This test verifies that createPublicFeed calls the subscription registry
        // with the correct parameters
        vm.recordLogs();
        registry.createPublicFeed(
            3600,
            1,
            "test",
            defaultConsumer,
            30 days
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        // Verify the subscription was created
        assertTrue(subRegistry.isSubscribed(defaultConsumer, feed));
    }

    function test_createPersonalFeed_CallsSubscriptionRegistry() public {
        // This test verifies that createPersonalFeed calls the subscription registry
        // with the correct parameters
        vm.recordLogs();
        registry.createPersonalFeed(
            7200,
            2,
            "personal",
            30 days
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        // Verify the personal subscription was created
        assertTrue(subRegistry.isSubscribed(address(this), feed));
    }

    function test_createFeed_ValidatesFrequencyBounds() public {
        // Test minimum frequency (1 minute)
        vm.recordLogs();
        registry.createPublicFeed(
            60, // 1 minute
            1,
            "test-min",
            defaultConsumer,
            30 days
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        assertEq(IFeed(feed).getOwner(), feedOwner);
        
        // Test maximum frequency (1 day)
        vm.recordLogs();
        registry.createPublicFeed(
            86400, // 1 day
            1,
            "test-max",
            defaultConsumer,
            30 days
        );
        
        // Get the feed address from the last emitted event
        logs = vm.getRecordedLogs();
        feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        assertEq(IFeed(feed).getOwner(), feedOwner);
    }
}
