// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {FeedRegistry} from "../src/FeedRegistry.sol";
import {IFeedRegistry} from "../src/interfaces/IFeedRegistry.sol";
import {IFeed} from "../src/interfaces/IFeed.sol";
import {MockAccessControlManager} from "./mocks/MockAccessControlManager.sol";
import {MockSubscriptionRegistry} from "./mocks/MockSubscriptionRegistry.sol";

contract FeedRegistryTest is Test {
    FeedRegistry registry;
    MockSubscriptionRegistry subRegistry;
    MockAccessControlManager acl;

    address manager;
    address notManager = address(999);
    address feedOwner = address(123);
    address defaultConsumer = address(456);

    function setUp() public {
        manager = address(this); // Use the test contract as manager
        acl = new MockAccessControlManager(manager);
        subRegistry = new MockSubscriptionRegistry();
        
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
            subscriptionDueTime: block.timestamp + 30 days,
            consumerPricePerSecondScaled: 0
        });
        params.defaultConsumers[0] = defaultConsumer;
        vm.prank(feedOwner);
        registry.createFeed(params);
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        // The LogFeedCreated event should be emitted
        // event LogFeedCreated(address indexed feed, IFeed.FeedType feedType, uint256 frequency, uint256 minSignaturesThreshold, string ipfsCID)
        assertEq(entries.length, 1); // Only LogFeedCreated event (MockSubscriptionRegistry doesn't emit events)
        
        // Check that the event was emitted with correct signature
        // LogFeedCreated signature should match IFeedRegistry interface
        bytes32 expectedEventSignature = keccak256("LogFeedCreated(address,uint8,uint256,uint256,string)");
        assertEq(entries[0].topics[0], expectedEventSignature);
        
        address feedAddress = address(uint160(uint256(entries[0].topics[1])));
        IFeed feed = IFeed(feedAddress);
        assertEq(uint8(feed.getFeedType()), uint8(IFeed.FeedType.PUBLIC));
        assertEq(feed.getFrequency(), 3600);
        assertEq(feed.getMinSignaturesThreshold(), 1);
        assertEq(feed.getOwner(), feedOwner);
    }

    function test_createFeed_PersonalFeed() public {
        vm.recordLogs();
        
        IFeedRegistry.CreateFeedParams memory params = IFeedRegistry.CreateFeedParams({
            feedType: IFeed.FeedType.PERSONAL,
            frequency: 3600,
            minSignaturesThreshold: 1,
            ipfsCID: "test",
            defaultConsumers: new address[](1),
            subscriptionDueTime: block.timestamp + 30 days,
            consumerPricePerSecondScaled: 0
        });
        params.defaultConsumers[0] = defaultConsumer;

        vm.prank(feedOwner);
        registry.createFeed(params);
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        // The LogFeedCreated event should be emitted
        // event LogFeedCreated(address indexed feed, IFeed.FeedType feedType, uint256 frequency, uint256 minSignaturesThreshold, string ipfsCID)
        assertEq(entries.length, 1); // Only LogFeedCreated event (MockSubscriptionRegistry doesn't emit events)
        
        // Check that the event was emitted with correct signature
        bytes32 expectedEventSignature = keccak256("LogFeedCreated(address,uint8,uint256,uint256,string)");
        assertEq(entries[0].topics[0], expectedEventSignature);
        
        address feedAddress = address(uint160(uint256(entries[0].topics[1])));
        IFeed feed = IFeed(feedAddress);
        assertEq(uint8(feed.getFeedType()), uint8(IFeed.FeedType.PERSONAL));
        assertEq(feed.getFrequency(), 3600);
        assertEq(feed.getMinSignaturesThreshold(), 1);
        assertEq(feed.getOwner(), feedOwner);
    }

    function test_createFeed_InvalidConfig_ZeroThreshold() public {
        IFeedRegistry.CreateFeedParams memory params = IFeedRegistry.CreateFeedParams({
            feedType: IFeed.FeedType.PUBLIC,
            frequency: 3600,
            minSignaturesThreshold: 0, // Invalid
            ipfsCID: "test",
            defaultConsumers: new address[](1),
            subscriptionDueTime: block.timestamp + 30 days,
            consumerPricePerSecondScaled: 0
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
            subscriptionDueTime: block.timestamp + 30 days,
            consumerPricePerSecondScaled: 0
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
            subscriptionDueTime: block.timestamp + 30 days,
            consumerPricePerSecondScaled: 0
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
            subscriptionDueTime: block.timestamp - 1, // Invalid - past time
            consumerPricePerSecondScaled: 0
        });
        params.defaultConsumers[0] = defaultConsumer;
        
        vm.expectRevert(IFeedRegistry.InvalidFeedConfig.selector);
        registry.createFeed(params);
    }



    function test_supportsInterface() public {
        assertTrue(registry.supportsInterface(type(IFeedRegistry).interfaceId), "Should support IFeedRegistry interface");
    }
}
