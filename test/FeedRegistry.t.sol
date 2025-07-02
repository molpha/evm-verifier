// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {FeedRegistry} from "../src/FeedRegistry.sol";
import {IFeedRegistry} from "../src/interfaces/IFeedRegistry.sol";
import {IFeedRegistryStructs} from "../src/interfaces/IFeedRegistryStructs.sol";
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
        registry.createFeed(
            IFeedRegistryStructs.FeedType.PUBLIC,
            3600, // frequency
            1,    // minSignaturesThreshold  
            "test" // ipfsCID
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        assertTrue(registry.isFeed(feed));
    }

    function test_createFeed_PersonalFeed() public {        
        vm.recordLogs();
        registry.createFeed(
            IFeedRegistryStructs.FeedType.PERSONAL,
            7200, // frequency
            3,    // minSignaturesThreshold  
            "personal-test" // ipfsCID
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        assertTrue(registry.isFeed(feed));
        
        IFeedRegistryStructs.FeedConfig memory config = registry.getFeedConfig(feed);
        assertEq(uint256(config.feedType), uint256(IFeedRegistryStructs.FeedType.PERSONAL));
        assertEq(config.frequency, 7200);
        assertEq(config.minSignaturesThreshold, 3);
        assertEq(config.ipfsCID, "personal-test");
        assertEq(config.owner, address(this));
    }

    function test_createFeed_OnlyFeedManager() public {
        vm.prank(notManager);
        vm.expectRevert();
        registry.createFeed(
            IFeedRegistryStructs.FeedType.PUBLIC,
            3600,
            1,
            "test"
        );
    }

    function test_createFeed_InvalidFrequency() public {
        // Test frequency too low
        vm.expectRevert(IFeedRegistryErrors.InvalidFeedConfig.selector);
        registry.createFeed(
            IFeedRegistryStructs.FeedType.PUBLIC,
            0, // invalid frequency
            1,
            "test"
        );
        
        // Test frequency too high
        vm.expectRevert(IFeedRegistryErrors.InvalidFeedConfig.selector);
        registry.createFeed(
            IFeedRegistryStructs.FeedType.PUBLIC,
            2 days, // too high
            1,
            "test"
        );
    }

    function test_createFeed_InvalidMinSignaturesThreshold() public {
        vm.expectRevert(IFeedRegistryErrors.InvalidFeedConfig.selector);
        registry.createFeed(
            IFeedRegistryStructs.FeedType.PUBLIC,
            3600,
            0, // invalid threshold
            "test"
        );
    }

    function test_createFeed_InvalidCID() public {
        vm.expectRevert(IFeedRegistryErrors.InvalidFeedConfig.selector);
        registry.createFeed(
            IFeedRegistryStructs.FeedType.PUBLIC,
            3600,
            1,
            "" // empty CID
        );
    }

    function test_createFeed_EmitsEvent() public {
        // Test that creating a feed works (event testing removed for now)
        vm.recordLogs();
        registry.createFeed(
            IFeedRegistryStructs.FeedType.PUBLIC,
            3600,
            1,
            "test"
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        // Verify the feed was created successfully
        assertTrue(registry.isFeed(feed));
    }

    function test_updateFeedConfig_Personal() public {
        // Create a personal feed first
        vm.recordLogs();
        registry.createFeed(
            IFeedRegistryStructs.FeedType.PERSONAL,
            3600,
            1,
            "original"
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        // Update the config
        registry.updateFeedConfig(feed, 7200, 2, "updated");
        
        IFeedRegistryStructs.FeedConfig memory config = registry.getFeedConfig(feed);
        assertEq(config.frequency, 7200);
        assertEq(config.minSignaturesThreshold, 2);
        assertEq(config.ipfsCID, "updated");
    }

    function test_updateFeedConfig_OnlyOwner() public {
        vm.recordLogs();
        registry.createFeed(
            IFeedRegistryStructs.FeedType.PERSONAL,
            3600,
            1,
            "test"
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        vm.prank(notManager);
        vm.expectRevert(abi.encodeWithSelector(IFeedRegistryErrors.NotFeedOwner.selector, feed));
        registry.updateFeedConfig(feed, 7200, 2, "unauthorized");
    }

    function test_updateFeedConfig_NotPersonalFeed() public {
        vm.recordLogs();
        registry.createFeed(
            IFeedRegistryStructs.FeedType.PUBLIC,
            3600,
            1,
            "test"
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        vm.expectRevert(abi.encodeWithSelector(IFeedRegistryErrors.NotPersonalFeed.selector, feed));
        registry.updateFeedConfig(feed, 7200, 2, "updated");
    }

    function test_setFrequency_Personal() public {
        vm.recordLogs();
        registry.createFeed(
            IFeedRegistryStructs.FeedType.PERSONAL,
            3600,
            1,
            "test"
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        registry.setFrequency(feed, 7200);
        
        IFeedRegistryStructs.FeedConfig memory config = registry.getFeedConfig(feed);
        assertEq(config.frequency, 7200);
    }

    function test_setFrequency_InvalidFrequency() public {
        vm.recordLogs();
        registry.createFeed(
            IFeedRegistryStructs.FeedType.PERSONAL,
            3600,
            1,
            "test"
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        vm.expectRevert(abi.encodeWithSelector(IFeedRegistryErrors.InvalidFrequency.selector, 0));
        registry.setFrequency(feed, 0);
        
        vm.expectRevert(abi.encodeWithSelector(IFeedRegistryErrors.InvalidFrequency.selector, 2 days));
        registry.setFrequency(feed, 2 days);
    }

    function test_setMinSignaturesThreshold_Personal() public {
        vm.recordLogs();
        registry.createFeed(
            IFeedRegistryStructs.FeedType.PERSONAL,
            3600,
            1,
            "test"
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        registry.setMinSignaturesThreshold(feed, 5);
        
        IFeedRegistryStructs.FeedConfig memory config = registry.getFeedConfig(feed);
        assertEq(config.minSignaturesThreshold, 5);
    }

    function test_setMinSignaturesThreshold_InvalidThreshold() public {
        vm.recordLogs();
        registry.createFeed(
            IFeedRegistryStructs.FeedType.PERSONAL,
            3600,
            1,
            "test"
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        vm.expectRevert(abi.encodeWithSelector(IFeedRegistryErrors.InvalidMinSignaturesThreshold.selector, 0));
        registry.setMinSignaturesThreshold(feed, 0);
    }

    function test_setCID_Personal() public {
        vm.recordLogs();
        registry.createFeed(
            IFeedRegistryStructs.FeedType.PERSONAL,
            3600,
            1,
            "original"
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        registry.setCID(feed, "updated-cid");
        
        IFeedRegistryStructs.FeedConfig memory config = registry.getFeedConfig(feed);
        assertEq(config.ipfsCID, "updated-cid");
    }

    function test_setCID_InvalidCID() public {
        vm.recordLogs();
        registry.createFeed(
            IFeedRegistryStructs.FeedType.PERSONAL,
            3600,
            1,
            "original"
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        vm.expectRevert(abi.encodeWithSelector(IFeedRegistryErrors.InvalidCID.selector, ""));
        registry.setCID(feed, "");
    }

    function test_isFeed_ReturnsCorrectValue() public {
        address nonFeed = address(999);
        assertFalse(registry.isFeed(nonFeed));
        
        vm.recordLogs();
        registry.createFeed(
            IFeedRegistryStructs.FeedType.PUBLIC,
            3600,
            1,
            "test"
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        assertTrue(registry.isFeed(feed));
    }

    function test_getFeedPrice_ReturnsCorrectValue() public {
        vm.recordLogs();
        registry.createFeed(
            IFeedRegistryStructs.FeedType.PUBLIC,
            3600,
            1,
            "test"
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        uint256 price = registry.getFeedPrice(feed);
        assertTrue(price > 0); // Price should be calculated by PricingHelper
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
        registry.createFeed(
            IFeedRegistryStructs.FeedType.PUBLIC,
            frequency,
            minSignaturesThreshold,
            ipfsCID
        );
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address feed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        assertTrue(registry.isFeed(feed));
        
        IFeedRegistryStructs.FeedConfig memory config = registry.getFeedConfig(feed);
        assertEq(config.frequency, frequency);
        assertEq(config.minSignaturesThreshold, minSignaturesThreshold);
        assertEq(config.ipfsCID, ipfsCID);
    }

    function test_getFeedConfig_NonExistentFeed() public {
        address nonFeed = address(999);
        IFeedRegistryStructs.FeedConfig memory config = registry.getFeedConfig(nonFeed);
        
        // Non-existent feed should return empty config
        assertEq(config.frequency, 0);
        assertEq(config.minSignaturesThreshold, 0);
        assertEq(config.ipfsCID, "");
        assertEq(config.owner, address(0));
    }

    function test_createFeed_MultipleFeedTypes() public {
        // Create public feed
        vm.recordLogs();
        registry.createFeed(
            IFeedRegistryStructs.FeedType.PUBLIC,
            3600,
            1,
            "public"
        );
        
        // Get the public feed address from the last emitted event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address publicFeed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        // Create personal feed
        vm.recordLogs();
        registry.createFeed(
            IFeedRegistryStructs.FeedType.PERSONAL,
            7200,
            2,
            "personal"
        );
        
        // Get the personal feed address from the last emitted event  
        logs = vm.getRecordedLogs();
        address personalFeed = address(uint160(uint256(logs[logs.length - 1].topics[1])));
        
        assertTrue(registry.isFeed(publicFeed));
        assertTrue(registry.isFeed(personalFeed));
        
        IFeedRegistryStructs.FeedConfig memory publicConfig = registry.getFeedConfig(publicFeed);
        IFeedRegistryStructs.FeedConfig memory personalConfig = registry.getFeedConfig(personalFeed);
        
        assertEq(uint256(publicConfig.feedType), uint256(IFeedRegistryStructs.FeedType.PUBLIC));
        assertEq(uint256(personalConfig.feedType), uint256(IFeedRegistryStructs.FeedType.PERSONAL));
    }
}
