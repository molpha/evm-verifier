// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {FeedRegistry} from "../src/FeedRegistry.sol";
import {IFeedRegistry} from "../src/interfaces/IFeedRegistry.sol";
import {IFeed} from "../src/interfaces/IFeed.sol";
import {MockAccessControlManager} from "./mocks/MockAccessControlManager.sol";
import {MockSubscriptionRegistry} from "./mocks/MockSubscriptionRegistry.sol";
import {IDataSourceRegistry} from "../src/interfaces/IDataSourceRegistry.sol";
import {MockDataSourceRegistry} from "./mocks/MockDataSourceRegistry.sol";

contract FeedRegistryTest is Test {
    FeedRegistry registry;
    MockSubscriptionRegistry subRegistry;
    MockAccessControlManager acl;
    MockDataSourceRegistry dataSourceRegistry;

    address manager;
    address notManager = address(999);
    address feedOwner = address(123);
    address defaultConsumer = address(456);

    function setUp() public {
        manager = address(this); // Use the test contract as manager
        acl = new MockAccessControlManager(manager);
        subRegistry = new MockSubscriptionRegistry();
        dataSourceRegistry = new MockDataSourceRegistry();
        
        // Set feed manager for proper access control
        acl.setFeedManager(manager);
        
        registry = new FeedRegistry();
        registry.initialize(address(acl), address(subRegistry), address(dataSourceRegistry));
        
        // Set the FeedRegistry address in the access control manager
        acl.setFeedRegistry(address(registry));
    }

    function test_createFeed_PublicFeed() public {        
        vm.recordLogs();
        IDataSourceRegistry.DataSource memory dataSource = IDataSourceRegistry.DataSource({
            owner: feedOwner,
            dataSourceType: IDataSourceRegistry.DataSourceType.Public,
            source: "test",
            name: "test"
        });
        IFeedRegistry.CreateDataSourceParams memory dataSourceParams = IFeedRegistry.CreateDataSourceParams({
            dataSource: dataSource,
            signature: ""
        });
        IFeedRegistry.CreateFeedParams memory params = IFeedRegistry.CreateFeedParams({
            feedType: IFeed.FeedType.PUBLIC,
            frequency: 3600,
            minSignaturesThreshold: 1,
            feedId: bytes32(uint256(1)),
            defaultConsumers: new address[](1),
            subscriptionDueTime: uint64(block.timestamp + 30 days),
            consumerPricePerSecondScaled: 0
        });

        params.defaultConsumers[0] = defaultConsumer;
        vm.prank(feedOwner);
        registry.createFeedWithNewDataSource(params, dataSourceParams);
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        // Now we expect 2 events: DataSourceCreated and LogFeedCreated
        assertEq(entries.length, 2); // DataSourceCreated and LogFeedCreated events
        
        // Check that the LogFeedCreated event was emitted with correct signature (second event)
        // LogFeedCreated signature should match IFeedRegistry interface
        bytes32 expectedEventSignature = keccak256("LogFeedCreated(address,uint8,uint256,uint256,string)");
        assertEq(entries[1].topics[0], expectedEventSignature);
        
        address feedAddress = address(uint160(uint256(entries[1].topics[1])));
        IFeed feed = IFeed(feedAddress);
        assertEq(uint8(feed.getFeedType()), uint8(IFeed.FeedType.PUBLIC));
        assertEq(feed.getFrequency(), 3600);
        assertEq(feed.getMinSignaturesThreshold(), 1);
        assertEq(feed.getOwner(), feedOwner);
    }

    function test_createFeed_PersonalFeed() public {
        vm.recordLogs();
        IDataSourceRegistry.DataSource memory dataSource = IDataSourceRegistry.DataSource({
            owner: feedOwner,
            dataSourceType: IDataSourceRegistry.DataSourceType.Public,
            source: "test",
            name: "test"
        });
        IFeedRegistry.CreateDataSourceParams memory dataSourceParams = IFeedRegistry.CreateDataSourceParams({
            dataSource: dataSource,
            signature: ""
        });
        
        IFeedRegistry.CreateFeedParams memory params = IFeedRegistry.CreateFeedParams({
            feedType: IFeed.FeedType.PERSONAL,
            frequency: 3600,
            minSignaturesThreshold: 1,
            feedId: bytes32(uint256(1)),
            defaultConsumers: new address[](1),
            subscriptionDueTime: uint64(block.timestamp + 30 days),
            consumerPricePerSecondScaled: 0
        });
        params.defaultConsumers[0] = defaultConsumer;

        vm.prank(feedOwner);
        registry.createFeedWithNewDataSource(params, dataSourceParams);
        
        // Get the feed address from the last emitted event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        // Now we expect 2 events: DataSourceCreated and LogFeedCreated
        assertEq(entries.length, 2); // DataSourceCreated and LogFeedCreated events
        
        // Check that the LogFeedCreated event was emitted with correct signature (second event)
        bytes32 expectedEventSignature = keccak256("LogFeedCreated(address,uint8,uint256,uint256,string)");
        assertEq(entries[1].topics[0], expectedEventSignature);
        
        address feedAddress = address(uint160(uint256(entries[1].topics[1])));
        IFeed feed = IFeed(feedAddress);
        assertEq(uint8(feed.getFeedType()), uint8(IFeed.FeedType.PERSONAL));
        assertEq(feed.getFrequency(), 3600);
        assertEq(feed.getMinSignaturesThreshold(), 1);
        assertEq(feed.getOwner(), feedOwner);
    }

    function test_createFeed_InvalidConfig_ZeroThreshold() public {
        IDataSourceRegistry.DataSource memory dataSource = IDataSourceRegistry.DataSource({
            owner: feedOwner,
            dataSourceType: IDataSourceRegistry.DataSourceType.Public,
            source: "test",
            name: "test"
        });
        IFeedRegistry.CreateDataSourceParams memory dataSourceParams = IFeedRegistry.CreateDataSourceParams({
            dataSource: dataSource,
            signature: ""
        });
        IFeedRegistry.CreateFeedParams memory params = IFeedRegistry.CreateFeedParams({
            feedType: IFeed.FeedType.PUBLIC,
            frequency: 3600,
            minSignaturesThreshold: 0, // Invalid
            feedId: bytes32(uint256(1)),
            defaultConsumers: new address[](1),
            subscriptionDueTime: uint64(block.timestamp + 30 days),
            consumerPricePerSecondScaled: 0
        });
        params.defaultConsumers[0] = defaultConsumer;
        
        vm.expectRevert(IFeedRegistry.InvalidFeedConfig.selector);
        registry.createFeedWithNewDataSource(params, dataSourceParams);
    }

    function test_createFeed_InvalidConfig_ZeroFrequency() public {
        IDataSourceRegistry.DataSource memory dataSource = IDataSourceRegistry.DataSource({
            owner: feedOwner,
            dataSourceType: IDataSourceRegistry.DataSourceType.Public,
            source: "test",
            name: "test"
        });
        IFeedRegistry.CreateDataSourceParams memory dataSourceParams = IFeedRegistry.CreateDataSourceParams({
            dataSource: dataSource,
            signature: ""
        });
        IFeedRegistry.CreateFeedParams memory params = IFeedRegistry.CreateFeedParams({
            feedType: IFeed.FeedType.PUBLIC,
            frequency: 0, // Invalid
            minSignaturesThreshold: 1,
            feedId: bytes32(uint256(1)),
            defaultConsumers: new address[](1),
            subscriptionDueTime: uint64(block.timestamp + 30 days),
            consumerPricePerSecondScaled: 0
        });
        params.defaultConsumers[0] = defaultConsumer;
        
        vm.expectRevert(IFeedRegistry.InvalidFeedConfig.selector);
        registry.createFeedWithNewDataSource(params, dataSourceParams);
    }

    function test_createFeed_InvalidConfig_EmptyCID() public {
        IDataSourceRegistry.DataSource memory dataSource = IDataSourceRegistry.DataSource({
            owner: feedOwner,
            dataSourceType: IDataSourceRegistry.DataSourceType.Public,
            source: "test",
            name: "test"
        });
        IFeedRegistry.CreateDataSourceParams memory dataSourceParams = IFeedRegistry.CreateDataSourceParams({
            dataSource: dataSource,
            signature: ""
        });
        IFeedRegistry.CreateFeedParams memory params = IFeedRegistry.CreateFeedParams({
            feedType: IFeed.FeedType.PUBLIC,
            frequency: 3600,
            minSignaturesThreshold: 1,
            feedId: bytes32(0), // Invalid
            defaultConsumers: new address[](1),
            subscriptionDueTime: uint64(block.timestamp + 30 days),
            consumerPricePerSecondScaled: 0
        });
        params.defaultConsumers[0] = defaultConsumer;
        
        vm.expectRevert(IFeedRegistry.InvalidFeedConfig.selector);
        registry.createFeedWithNewDataSource(params, dataSourceParams);
    }

    function test_createFeed_InvalidConfig_PastDueTime() public {
        IDataSourceRegistry.DataSource memory dataSource = IDataSourceRegistry.DataSource({
            owner: feedOwner,
            dataSourceType: IDataSourceRegistry.DataSourceType.Public,
            source: "test",
            name: "test"
        });
        IFeedRegistry.CreateDataSourceParams memory dataSourceParams = IFeedRegistry.CreateDataSourceParams({
            dataSource: dataSource,
            signature: ""
        });
        IFeedRegistry.CreateFeedParams memory params = IFeedRegistry.CreateFeedParams({
            feedType: IFeed.FeedType.PUBLIC,
            frequency: 3600,
            minSignaturesThreshold: 1,
            feedId: bytes32(uint256(1)),
            defaultConsumers: new address[](1),
            subscriptionDueTime: uint64(block.timestamp - 1), // Invalid - past time
            consumerPricePerSecondScaled: 0
        });
        params.defaultConsumers[0] = defaultConsumer;
        
        vm.expectRevert(IFeedRegistry.InvalidFeedConfig.selector);
        registry.createFeedWithNewDataSource(params, dataSourceParams);
    }

    function test_supportsInterface() public view {
        assertTrue(registry.supportsInterface(type(IFeedRegistry).interfaceId), "Should support IFeedRegistry interface");
    }
}
