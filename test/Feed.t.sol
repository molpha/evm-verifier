// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {PublicFeed} from "../src/PublicFeed.sol";
import {PersonalFeed} from "../src/PersonalFeed.sol";
import {IFeed} from "../src/interfaces/IFeed.sol";
import {IFeedStructs} from "../src/interfaces/IFeedStructs.sol";
import {IFeedEvents} from "../src/interfaces/IFeedEvents.sol";
import {MockAccessControlManager} from "./mocks/MockAccessControlManager.sol";
import {MockSubscriptionRegistry} from "./mocks/MockSubscriptionRegistry.sol";
import {MockNodeRegistry} from "./mocks/MockNodeRegistry.sol";

contract FeedTest is Test {
    PublicFeed publicFeed;
    PersonalFeed personalFeed;
    MockAccessControlManager acl;
    MockSubscriptionRegistry subRegistry;
    MockNodeRegistry nodeRegistry;
    
    address feedOwner = address(1);
    address consumer = address(2);
    address nonConsumer = address(3);

    function setUp() public {
        acl = new MockAccessControlManager(address(this));
        subRegistry = new MockSubscriptionRegistry();
        nodeRegistry = new MockNodeRegistry();
        
        // Set up access control
        acl.setNodeRegistry(address(nodeRegistry));
        
        // Deploy feeds
        publicFeed = new PublicFeed(
            address(acl),
            address(subRegistry),
            feedOwner,
            3600, // frequency
            1, // minSignaturesThreshold
            "QmTestPublic"
        );
        
        personalFeed = new PersonalFeed(
            address(acl),
            address(subRegistry),
            feedOwner,
            3600, // frequency
            1, // minSignaturesThreshold
            "QmTestPersonal"
        );
        
        // Set up subscription for consumer
        subRegistry.setSubscribed(consumer, address(publicFeed), true);
        subRegistry.setSubscribed(consumer, address(personalFeed), true);
    }

    // Public Feed Tests
    function test_publicFeed_getFeedType() public {
        assertEq(uint8(publicFeed.getFeedType()), uint8(IFeed.FeedType.PUBLIC));
    }

    function test_publicFeed_getOwner() public {
        assertEq(publicFeed.getOwner(), feedOwner);
    }

    function test_publicFeed_getLatest_subscribedUser() public {
        vm.prank(consumer);
        (bytes memory value, uint256 timestamp) = publicFeed.getLatest();
        assertEq(value, "");
        assertEq(timestamp, 0);
    }

    function test_publicFeed_getLatest_nonSubscribedUser() public {
        vm.prank(nonConsumer);
        vm.expectRevert();
        publicFeed.getLatest();
    }

    // Personal Feed Tests
    function test_personalFeed_getFeedType() public {
        assertEq(uint8(personalFeed.getFeedType()), uint8(IFeed.FeedType.PERSONAL));
    }

    function test_personalFeed_getOwner() public {
        assertEq(personalFeed.getOwner(), feedOwner);
    }

    function test_personalFeed_getLatest_subscribedUser() public {
        vm.prank(consumer);
        (bytes memory value, uint256 timestamp) = personalFeed.getLatest();
        assertEq(value, "");
        assertEq(timestamp, 0);
    }

    function test_personalFeed_getLatest_nonSubscribedUser() public {
        vm.prank(nonConsumer);
        vm.expectRevert();
        personalFeed.getLatest();
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

    function test_publicFeed_getSubscriptionRegistry() public {
        assertEq(address(publicFeed.getSubscriptionRegistry()), address(subRegistry));
    }

    function test_personalFeed_getSubscriptionRegistry() public {
        assertEq(address(personalFeed.getSubscriptionRegistry()), address(subRegistry));
    }

    function test_publicFeed_getMinSignaturesThreshold() public {
        assertEq(publicFeed.getMinSignaturesThreshold(), 1);
    }

    function test_personalFeed_getMinSignaturesThreshold() public {
        assertEq(personalFeed.getMinSignaturesThreshold(), 1);
    }

    function test_publicFeed_supportsInterface() public {
        assertTrue(publicFeed.supportsInterface(type(IFeed).interfaceId));
    }

    function test_personalFeed_supportsInterface() public {
        assertTrue(personalFeed.supportsInterface(type(IFeed).interfaceId));
    }

    function test_personalFeed_updateFeedConfig_onlyOwner() public {
        vm.prank(feedOwner);
        personalFeed.updateFeedConfig(7200, 2, "newCID");
        
        // Verify changes
        assertEq(personalFeed.getMinSignaturesThreshold(), 2);
    }

    function test_personalFeed_updateFeedConfig_notOwner() public {
        vm.prank(nonConsumer);
        vm.expectRevert();
        personalFeed.updateFeedConfig(7200, 2, "newCID");
    }
}
