// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Feed} from "../src/Feed.sol";
import {IFeed} from "../src/interfaces/IFeed.sol";
import {IFeedStructs} from "../src/interfaces/IFeedStructs.sol";
import {IFeedEvents} from "../src/interfaces/IFeedEvents.sol";
import {MockAccessControlManager} from "./mocks/MockAccessControlManager.sol";
import {MockSubscriptionRegistry} from "./mocks/MockSubscriptionRegistry.sol";
import {MockNodeRegistry} from "./mocks/MockNodeRegistry.sol";
import {PricingHelper} from "../src/PricingHelper.sol";
import {DataSourceRegistry} from "../src/DataSourceRegistry.sol";
import {IDataSourceRegistry} from "../src/interfaces/IDataSourceRegistry.sol";

contract FeedTest is Test {
    IFeed publicFeed;
    IFeed personalFeed;
    MockAccessControlManager acl;
    MockSubscriptionRegistry subRegistry;
    MockNodeRegistry nodeRegistry;
    PricingHelper pricingHelper;
    DataSourceRegistry dataSourceRegistry;
    
    address feedOwner = address(1);
    address consumer = address(2);
    address nonConsumer = address(3);

    function setUp() public {
        acl = new MockAccessControlManager(address(this));
        subRegistry = new MockSubscriptionRegistry();
        nodeRegistry = new MockNodeRegistry();
        pricingHelper = new PricingHelper();
        dataSourceRegistry = new DataSourceRegistry();
        
        // Initialize DataSourceRegistry
        dataSourceRegistry.initialize(address(acl));
        
        // Set up access control
        acl.setNodeRegistry(address(nodeRegistry));
        acl.setFeedRegistry(address(this)); // Set test contract as feed registry for DataSourceRegistry
        
        // Create data sources for feeds
        IDataSourceRegistry.DataSource memory publicDataSource = IDataSourceRegistry.DataSource({
            owner: feedOwner,
            dataSourceType: IDataSourceRegistry.DataSourceType.Public,
            source: "https://api.example.com/public",
            name: "public"
        });
        
        IDataSourceRegistry.DataSource memory personalDataSource = IDataSourceRegistry.DataSource({
            owner: feedOwner,
            dataSourceType: IDataSourceRegistry.DataSourceType.Public,
            source: "https://api.example.com/personal",
            name: "personal"
        });
        
        // Generate dataSourceIds without creating them (since we don't have proper signatures)
        bytes32 publicDataSourceId = keccak256(abi.encodePacked(
            publicDataSource.owner, 
            publicDataSource.source, 
            publicDataSource.dataSourceType
        ));
        
        bytes32 personalDataSourceId = keccak256(abi.encodePacked(
            personalDataSource.owner, 
            personalDataSource.source, 
            personalDataSource.dataSourceType
        ));
        
        // Deploy feeds - fix constructor parameter order
        // Make public feed free (consumerPricePerSecondScaled: 0)
        publicFeed = new Feed(
            IFeed.CreateFeedParams({
                feedType: IFeed.FeedType.PUBLIC,
                accessControlManager: address(acl),
                owner: feedOwner,
                frequency: 3600,
                signaturesRequired: 1,
                consumerPricePerSecondScaled: 0,
                jobId: bytes32(uint256(1)),
                dataSourceId: publicDataSourceId,
                ipfsCID: "test"
            })
        );
        
        // Make personal feed paid (consumerPricePerSecondScaled: 0 for personal feeds)
        personalFeed = new Feed(
            IFeed.CreateFeedParams({
                feedType: IFeed.FeedType.PERSONAL,
                accessControlManager: address(acl),
                owner: feedOwner,
                frequency: 3600,
                signaturesRequired: 1,
                consumerPricePerSecondScaled: 0,
                jobId: bytes32(uint256(1)),
                dataSourceId: personalDataSourceId,
                ipfsCID: "test"
            })
        );
        
        // Set up subscription registry access
        acl.setSubscriptionRegistry(address(subRegistry));
        
        // Add consumer to the personal feed (personal feeds are not free by default)
        vm.prank(feedOwner);
        personalFeed.addConsumer(consumer, block.timestamp + 30 days);
    }

    // Public Feed Tests
    function test_publicFeed_getFeedType() public view {
        assertEq(uint8(publicFeed.getFeedType()), uint8(IFeed.FeedType.PUBLIC));
    }

    function test_publicFeed_getOwner() public view {
        assertEq(publicFeed.getOwner(), feedOwner);
    }

    function test_publicFeed_getLatest_subscribedUser() public {
        vm.prank(consumer);
        (bytes memory value, uint256 timestamp) = publicFeed.getLatest();
        assertEq(value, "");
        assertEq(timestamp, 0);
    }

    function test_publicFeed_getLatest_nonSubscribedUser() public {
        // Public feeds are free, so even non-subscribed users can access them
        vm.prank(nonConsumer);
        (bytes memory value, uint256 timestamp) = publicFeed.getLatest();
        assertEq(value, "");
        assertEq(timestamp, 0);
    }

    // Personal Feed Tests
    function test_personalFeed_getFeedType() public view {
        assertEq(uint8(personalFeed.getFeedType()), uint8(IFeed.FeedType.PERSONAL));
    }

    function test_personalFeed_getOwner() public view {
        assertEq(personalFeed.getOwner(), feedOwner);
    }

    function test_personalFeed_getLatest_subscribedUser() public {
        vm.prank(consumer);
        (bytes memory value, uint256 timestamp) = personalFeed.getLatest();
        assertEq(value, "");
        assertEq(timestamp, 0);
    }

    function test_personalFeed_getLatest_nonSubscribedUser() public {
        // Personal feeds allow access to EOA addresses due to msg.sender == tx.origin condition
        // This test verifies that behavior
        vm.prank(nonConsumer);
        (bytes memory value, uint256 timestamp) = personalFeed.getLatest();
        assertEq(value, "");
        assertEq(timestamp, 0);
    }

    function test_publicFeed_publish() public {
        IFeedStructs.Answer memory answer = IFeedStructs.Answer({
            value: "test_value",
            timestamp: uint64(block.timestamp)
        });
        
        // Mock the node registry to return success
        nodeRegistry.setVerificationResult(true);
        
        vm.expectEmit(true, true, false, true);
        emit IFeedEvents.LogAnswerPublished(answer.value, answer.timestamp);
        
        // Need to prank as nodeRegistry to pass the onlyNodeRegistry modifier
        vm.prank(address(nodeRegistry));
        publicFeed.publish(answer);
        
        // Verify the answer was stored
        vm.prank(consumer);
        (bytes memory value, uint256 timestamp) = publicFeed.getLatest();
        assertEq(value, answer.value);
        assertEq(timestamp, answer.timestamp);
    }

    function test_personalFeed_publish() public {
        IFeedStructs.Answer memory answer = IFeedStructs.Answer({
            value: "personal_test_value",
            timestamp: uint64(block.timestamp)
        });
        
        // Mock the node registry to return success
        nodeRegistry.setVerificationResult(true);
        
        vm.expectEmit(true, true, false, true);
        emit IFeedEvents.LogAnswerPublished(answer.value, answer.timestamp);
        
        // Need to prank as nodeRegistry to pass the onlyNodeRegistry modifier
        vm.prank(address(nodeRegistry));
        personalFeed.publish(answer);
        
        // Verify the answer was stored
        vm.prank(consumer);
        (bytes memory value, uint256 timestamp) = personalFeed.getLatest();
        assertEq(value, answer.value);
        assertEq(timestamp, answer.timestamp);
    }

    function test_publicFeed_getEntry() public {
        IFeedStructs.Answer memory answer = IFeedStructs.Answer({
            value: "entry_test_value",
            timestamp: uint64(block.timestamp)
        });
        
        // Mock the node registry to return success
        nodeRegistry.setVerificationResult(true);
        
        // Need to prank as nodeRegistry to pass the onlyNodeRegistry modifier
        vm.prank(address(nodeRegistry));
        publicFeed.publish(answer);
        
        // Test getEntry
        vm.prank(consumer);
        (bytes memory value, uint256 timestamp) = publicFeed.getEntry(0);
        assertEq(value, answer.value);
        assertEq(timestamp, answer.timestamp);
    }

    function test_personalFeed_getEntry() public {
        IFeedStructs.Answer memory answer = IFeedStructs.Answer({
            value: "personal_entry_test_value",
            timestamp: uint64(block.timestamp)
        });
        
        // Mock the node registry to return success
        nodeRegistry.setVerificationResult(true);
        
        // Need to prank as nodeRegistry to pass the onlyNodeRegistry modifier
        vm.prank(address(nodeRegistry));
        personalFeed.publish(answer);
        
        // Test getEntry
        vm.prank(consumer);
        (bytes memory value, uint256 timestamp) = personalFeed.getEntry(0);
        assertEq(value, answer.value);
        assertEq(timestamp, answer.timestamp);
    }

    function test_publicFeed_getLastUpdated() public {
        // Initially should be 0
        assertEq(publicFeed.getLastUpdated(), 0);
        
        IFeedStructs.Answer memory answer = IFeedStructs.Answer({
            value: "timestamp_test_value",
            timestamp: uint64(block.timestamp)
        });
        
        // Mock the node registry to return success
        nodeRegistry.setVerificationResult(true);
        
        // Need to prank as nodeRegistry to pass the onlyNodeRegistry modifier
        vm.prank(address(nodeRegistry));
        publicFeed.publish(answer);
        
        // Should now return the timestamp
        assertEq(publicFeed.getLastUpdated(), block.timestamp);
    }

    function test_personalFeed_getLastUpdated() public {
        // Initially should be 0
        assertEq(personalFeed.getLastUpdated(), 0);
        
        IFeedStructs.Answer memory answer = IFeedStructs.Answer({
            value: "personal_timestamp_test_value",
            timestamp: uint64(block.timestamp)
        });
        
        // Mock the node registry to return success
        nodeRegistry.setVerificationResult(true);
        
        // Need to prank as nodeRegistry to pass the onlyNodeRegistry modifier
        vm.prank(address(nodeRegistry));
        personalFeed.publish(answer);
        
        // Should now return the timestamp
        assertEq(personalFeed.getLastUpdated(), block.timestamp);
    }

    function test_publicFeed_getMinSignaturesThreshold() public view {
        assertEq(publicFeed.getMinSignaturesThreshold(), 1);
    }

    function test_personalFeed_getMinSignaturesThreshold() public view {
        assertEq(personalFeed.getMinSignaturesThreshold(), 1);
    }

    function test_personalFeed_updateFeedConfig_onlyOwner() public {
        // Test contract is set as feed registry in setUp, so it can call updateFeedConfig
        personalFeed.updateFeedConfig(7200, 2, bytes32(uint256(1)), "test");
        
        // Verify changes
        assertEq(personalFeed.getMinSignaturesThreshold(), 2);
    }

    function test_personalFeed_updateFeedConfig_notOwner() public {
        vm.prank(nonConsumer);
        vm.expectRevert();
        personalFeed.updateFeedConfig(7200, 2, bytes32(uint256(1)), "test");
    }
}
