// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {FeedRegistry} from "../src/FeedRegistry.sol";
import {IFeedRegistry} from "../src/interfaces/IFeedRegistry.sol";
import {IFeed} from "../src/interfaces/IFeed.sol";
import {MockAccessControlManager} from "./mocks/MockAccessControlManager.sol";
import {MockSubscriptionRegistry} from "./mocks/MockSubscriptionRegistry.sol";
import {MockNodeRegistry} from "./mocks/MockNodeRegistry.sol";

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
        
        registry = new FeedRegistry();
        registry.initialize(address(acl), address(subRegistry));
    }

    function test_createFeed_PublicFeed() public {        
        vm.recordLogs();
        
        IFeedRegistry.CreateFeedParams memory params = IFeedRegistry.CreateFeedParams({
            feedType: IFeed.FeedType.PUBLIC,
            frequency: 3600,
            minSignaturesThreshold: 1,
            ipfsCID: "test",
            defaultConsumers: new address[](1),
            subscriptionDueTime: block.timestamp + 30 days
        });
        params.defaultConsumers[0] = defaultConsumer;
        
        registry.createFeed(params);
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertTrue(logs.length > 0, "No events emitted");
        
        // Check that the last event is LogFeedCreated
        bytes32 expectedTopic = keccak256("LogFeedCreated(address,uint8,uint256,uint256,uint256,string)");
        assertEq(logs[logs.length - 1].topics[0], expectedTopic, "Wrong event emitted");
        
        // Decode the feed address from the event
        address feedAddress = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        // Verify the feed is registered
        assertTrue(registry.isFeed(feedAddress), "Feed should be registered");
    }

    function test_createFeed_PersonalFeed() public {        
        vm.recordLogs();
        
        IFeedRegistry.CreateFeedParams memory params = IFeedRegistry.CreateFeedParams({
            feedType: IFeed.FeedType.PERSONAL,
            frequency: 3600,
            minSignaturesThreshold: 1,
            ipfsCID: "test",
            defaultConsumers: new address[](1),
            subscriptionDueTime: block.timestamp + 30 days
        });
        params.defaultConsumers[0] = defaultConsumer;
        
        registry.createFeed(params);
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertTrue(logs.length > 0, "No events emitted");
        
        // Check that the last event is LogFeedCreated
        bytes32 expectedTopic = keccak256("LogFeedCreated(address,uint8,uint256,uint256,uint256,string)");
        assertEq(logs[logs.length - 1].topics[0], expectedTopic, "Wrong event emitted");
        
        // Decode the feed address from the event
        address feedAddress = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        // Verify the feed is registered
        assertTrue(registry.isFeed(feedAddress), "Feed should be registered");
    }

    function test_createFeed_InvalidConfig_ZeroThreshold() public {
        IFeedRegistry.CreateFeedParams memory params = IFeedRegistry.CreateFeedParams({
            feedType: IFeed.FeedType.PUBLIC,
            frequency: 3600,
            minSignaturesThreshold: 0, // Invalid
            ipfsCID: "test",
            defaultConsumers: new address[](1),
            subscriptionDueTime: block.timestamp + 30 days
        });
        params.defaultConsumers[0] = defaultConsumer;
        
        vm.expectRevert(IFeedRegistry.InvalidFeedConfig.selector);
        registry.createFeed(params);
    }

    function test_createFeed_InvalidConfig_ZeroFrequency() public {
        IFeedRegistry.CreateFeedParams memory params = IFeedRegistry.CreateFeedParams({
            feedType: IFeed.FeedType.PUBLIC,
            frequency: 0, // Invalid
            minSignaturesThreshold: 1,
            ipfsCID: "test",
            defaultConsumers: new address[](1),
            subscriptionDueTime: block.timestamp + 30 days
        });
        params.defaultConsumers[0] = defaultConsumer;
        
        vm.expectRevert(IFeedRegistry.InvalidFeedConfig.selector);
        registry.createFeed(params);
    }

    function test_createFeed_InvalidConfig_EmptyCID() public {
        IFeedRegistry.CreateFeedParams memory params = IFeedRegistry.CreateFeedParams({
            feedType: IFeed.FeedType.PUBLIC,
            frequency: 3600,
            minSignaturesThreshold: 1,
            ipfsCID: "", // Invalid
            defaultConsumers: new address[](1),
            subscriptionDueTime: block.timestamp + 30 days
        });
        params.defaultConsumers[0] = defaultConsumer;
        
        vm.expectRevert(IFeedRegistry.InvalidFeedConfig.selector);
        registry.createFeed(params);
    }

    function test_createFeed_InvalidConfig_PastDueTime() public {
        IFeedRegistry.CreateFeedParams memory params = IFeedRegistry.CreateFeedParams({
            feedType: IFeed.FeedType.PUBLIC,
            frequency: 3600,
            minSignaturesThreshold: 1,
            ipfsCID: "test",
            defaultConsumers: new address[](1),
            subscriptionDueTime: block.timestamp - 1 // Invalid - past time
        });
        params.defaultConsumers[0] = defaultConsumer;
        
        vm.expectRevert(IFeedRegistry.InvalidFeedConfig.selector);
        registry.createFeed(params);
    }

    function test_isFeed_UnregisteredFeed() public {
        address randomFeed = address(0x123);
        assertFalse(registry.isFeed(randomFeed), "Random address should not be a feed");
    }

    function test_supportsInterface() public {
        assertTrue(registry.supportsInterface(type(IFeedRegistry).interfaceId), "Should support IFeedRegistry interface");
    }
}
