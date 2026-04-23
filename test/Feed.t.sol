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
        IDataSourceRegistry.DataSource
            memory publicDataSource = IDataSourceRegistry.DataSource({
                owner: feedOwner,
                dataSourceType: IDataSourceRegistry.DataSourceType.Public,
                source: "https://api.example.com/public",
                name: "public"
            });

        IDataSourceRegistry.DataSource
            memory personalDataSource = IDataSourceRegistry.DataSource({
                owner: feedOwner,
                dataSourceType: IDataSourceRegistry.DataSourceType.Public,
                source: "https://api.example.com/personal",
                name: "personal"
            });

        // Generate dataSourceIds without creating them (since we don't have proper signatures)
        bytes32 publicDataSourceId = keccak256(
            abi.encodePacked(
                publicDataSource.owner,
                publicDataSource.source,
                publicDataSource.dataSourceType
            )
        );

        bytes32 personalDataSourceId = keccak256(
            abi.encodePacked(
                personalDataSource.owner,
                personalDataSource.source,
                personalDataSource.dataSourceType
            )
        );

        // Deploy feeds - fix constructor parameter order
        // Make public feed free (consumerPricePerSecondScaled: 0)
        publicFeed = new Feed(
            IFeed.CreateFeedParams({
                feedType: IFeed.FeedType.PUBLIC,
                accessControlManager: address(acl),
                nodeRegistry: address(nodeRegistry),
                owner: feedOwner,
                frequency: 3600,
                signaturesRequired: 1,
                consumerPricePerSecondScaled: 0,
                jobId: bytes32(uint256(1)),
                dataSourceId: publicDataSourceId,
                ipfsCID: "test"
            })
        );

        personalFeed = new Feed(
            IFeed.CreateFeedParams({
                feedType: IFeed.FeedType.PERSONAL,
                accessControlManager: address(acl),
                nodeRegistry: address(nodeRegistry),
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
        assertEq(
            uint8(personalFeed.getFeedType()),
            uint8(IFeed.FeedType.PERSONAL)
        );
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
}
/*
    function test_chainlink_latestRoundData() public {
        // Create a proper int256 price value (e.g., 2000.00000000 with 8 decimals)
        int256 price = 200000000000; // 2000 * 10^8
        bytes memory valueBytes = abi.encode(price);

        IFeedStructs.Answer memory answer = IFeedStructs.Answer({
            value: valueBytes,
            timestamp: uint64(block.timestamp)
        });

        // Mock the node registry to return success
        nodeRegistry.setVerificationResult(true);

        // Publish the answer
        vm.prank(address(nodeRegistry));
        publicFeed.publish(answer);

        // Test latestRoundData
        vm.prank(consumer);
        (
            uint80 roundId,
            int256 returnedPrice,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = AggregatorV3Interface(address(publicFeed)).latestRoundData();

        assertEq(roundId, 0); // First round
        assertEq(returnedPrice, price);
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 0);
    }

    function test_chainlink_getRoundData() public {
        // Create a proper int256 price value
        int256 price = 300000000000; // 3000 * 10^8
        bytes memory valueBytes = abi.encode(price);

        IFeedStructs.Answer memory answer = IFeedStructs.Answer({
            value: valueBytes,
            timestamp: uint64(block.timestamp)
        });

        // Mock the node registry to return success
        nodeRegistry.setVerificationResult(true);

        // Publish the answer
        vm.prank(address(nodeRegistry));
        publicFeed.publish(answer);

        // Test getRoundData
        vm.prank(consumer);
        (
            uint80 roundId,
            int256 returnedPrice,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = AggregatorV3Interface(address(publicFeed)).getRoundData(
                0
            );

        assertEq(roundId, 0);
        assertEq(returnedPrice, price);
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 0);
    }

    function test_chainlink_getRoundData_invalidRound() public {
        vm.prank(consumer);
        vm.expectRevert("Invalid round ID");
        AggregatorV3Interface(address(publicFeed)).getRoundData(0);
    }

    function test_chainlink_latestRoundData_noData() public {
        vm.prank(consumer);
        vm.expectRevert("No data available");
        AggregatorV3Interface(address(publicFeed)).latestRoundData();
    }

    function test_chainlink_access_control() public {
        // Create a proper int256 price value
        int256 price = 150000000000; // 1500 * 10^8
        bytes memory valueBytes = abi.encode(price);

        IFeedStructs.Answer memory answer = IFeedStructs.Answer({
            value: valueBytes,
            timestamp: uint64(block.timestamp)
        });

        // Mock the node registry to return success
        nodeRegistry.setVerificationResult(true);

        // Publish the answer
        vm.prank(address(nodeRegistry));
        personalFeed.publish(answer);

        // Test that non-consumers cannot access personal feed via Chainlink interface
        vm.prank(nonConsumer);
        // Personal feeds allow EOA access, so this should work
        AggregatorV3Interface(address(personalFeed)).latestRoundData();

        // But for a paid personal feed, let's create one and test
        // This would require modifying the setup, but the access control is already tested above
    }

    // Comprehensive Chainlink Interface Tests
    function test_chainlink_dataConversion_differentSizes() public {
        nodeRegistry.setVerificationResult(true);

        // Test with exactly 32 bytes (valid)
        int256 price = 300000000000;
        bytes memory valueBytes = abi.encode(price);

        IFeedStructs.Answer memory answer = IFeedStructs.Answer({
            value: valueBytes,
            timestamp: uint64(block.timestamp)
        });

        vm.prank(address(nodeRegistry));
        publicFeed.publish(answer);

        vm.prank(consumer);
        (, int256 returnedPrice, , , ) = AggregatorV3Interface(
            address(publicFeed)
        ).latestRoundData();
        assertEq(returnedPrice, price);
    }

    function test_chainlink_dataConversion_invalidFormat() public {
        nodeRegistry.setVerificationResult(true);

        // Test with less than 32 bytes (should revert)
        bytes memory invalidValueBytes = abi.encodePacked(uint128(1000));

        IFeedStructs.Answer memory answer = IFeedStructs.Answer({
            value: invalidValueBytes,
            timestamp: uint64(block.timestamp)
        });

        vm.prank(address(nodeRegistry));
        publicFeed.publish(answer);

        vm.prank(consumer);
        vm.expectRevert("Invalid answer format");
        AggregatorV3Interface(address(publicFeed)).latestRoundData();
    }

    function test_chainlink_dataConversion_largeValues() public {
        nodeRegistry.setVerificationResult(true);

        // Test with large values
        int256 largePrice = type(int256).max / 2; // Very large positive number
        bytes memory valueBytes = abi.encode(largePrice);

        IFeedStructs.Answer memory answer = IFeedStructs.Answer({
            value: valueBytes,
            timestamp: uint64(block.timestamp)
        });

        vm.prank(address(nodeRegistry));
        publicFeed.publish(answer);

        vm.prank(consumer);
        (, int256 returnedPrice, , , ) = AggregatorV3Interface(
            address(publicFeed)
        ).latestRoundData();
        assertEq(returnedPrice, largePrice);
    }

    function test_chainlink_dataConversion_negativeValues() public {
        nodeRegistry.setVerificationResult(true);

        // Test with negative values
        int256 negativePrice = -150000000000; // -1500 * 10^8
        bytes memory valueBytes = abi.encode(negativePrice);

        IFeedStructs.Answer memory answer = IFeedStructs.Answer({
            value: valueBytes,
            timestamp: uint64(block.timestamp)
        });

        vm.prank(address(nodeRegistry));
        publicFeed.publish(answer);

        vm.prank(consumer);
        (, int256 returnedPrice, , , ) = AggregatorV3Interface(
            address(publicFeed)
        ).latestRoundData();
        assertEq(returnedPrice, negativePrice);
    }

    function test_chainlink_accessControl_personalFeed_nonConsumer() public {
        // Create a paid personal feed (but personal feeds must have consumerPricePerSecondScaled = 0)
        IFeed paidPersonalFeed = new Feed(
            IFeed.CreateFeedParams({
                feedType: IFeed.FeedType.PERSONAL,
                accessControlManager: address(acl),
                owner: feedOwner,
                frequency: 3600,
                signaturesRequired: 1,
                consumerPricePerSecondScaled: 0, // Personal feeds must be free
                jobId: bytes32(uint256(2)),
                dataSourceId: bytes32(uint256(2)),
                ipfsCID: "paid_test",
                decimals: 8,
                description: "Paid Personal Feed"
            })
        );

        // Publish data
        int256 price = 250000000000;
        bytes memory valueBytes = abi.encode(price);
        IFeedStructs.Answer memory answer = IFeedStructs.Answer({
            value: valueBytes,
            timestamp: uint64(block.timestamp)
        });

        nodeRegistry.setVerificationResult(true);
        vm.prank(address(nodeRegistry));
        paidPersonalFeed.publish(answer);

        // Non-consumer should be able to access if they're an EOA (msg.sender == tx.origin)
        vm.prank(nonConsumer);
        AggregatorV3Interface(address(paidPersonalFeed)).latestRoundData();

        // But a contract caller without subscription should fail
        // This would require setting up a mock contract caller, which is complex
        // The access control logic is already tested in the existing tests
    }

    function test_chainlink_roundBoundaries() public {
        nodeRegistry.setVerificationResult(true);

        // Test round ID boundaries
        vm.prank(consumer);
        vm.expectRevert("Invalid round ID");
        AggregatorV3Interface(address(publicFeed)).getRoundData(
            type(uint80).max
        );

        // Publish one answer and test boundary
        int256 price = 100000000000;
        bytes memory valueBytes = abi.encode(price);
        IFeedStructs.Answer memory answer = IFeedStructs.Answer({
            value: valueBytes,
            timestamp: uint64(block.timestamp)
        });

        vm.prank(address(nodeRegistry));
        publicFeed.publish(answer);

        // Should work for round 0
        vm.prank(consumer);
        AggregatorV3Interface(address(publicFeed)).getRoundData(0);

        // Should fail for round 1 (doesn't exist yet)
        vm.prank(consumer);
        vm.expectRevert("Invalid round ID");
        AggregatorV3Interface(address(publicFeed)).getRoundData(1);
    }

    function test_chainlink_timestampConsistency() public {
        nodeRegistry.setVerificationResult(true);

        uint256 publishTime = block.timestamp + 1000;
        vm.warp(publishTime);

        int256 price = 180000000000;
        bytes memory valueBytes = abi.encode(price);
        IFeedStructs.Answer memory answer = IFeedStructs.Answer({
            value: valueBytes,
            timestamp: uint64(publishTime)
        });

        vm.prank(address(nodeRegistry));
        publicFeed.publish(answer);

        // Check that all timestamp fields are consistent
        vm.prank(consumer);
        (, , uint256 startedAt, uint256 updatedAt, ) = AggregatorV3Interface(
            address(publicFeed)
        ).latestRoundData();

        assertEq(startedAt, publishTime);
        assertEq(updatedAt, publishTime);
        // In our implementation, startedAt == updatedAt for simplicity
    }

    function test_chainlink_dataIntegrity_multiplePublishers() public {
        nodeRegistry.setVerificationResult(true);

        // Simulate multiple publishers (though in our system only nodeRegistry can publish)
        int256[] memory prices = new int256[](5);
        uint256[] memory timestamps = new uint256[](5);

        for (uint i = 0; i < 5; i++) {
            prices[i] = int256(200000000000 + i * 10000000000); // Incrementing prices
            timestamps[i] = block.timestamp + i * 60; // 1 minute apart

            vm.warp(timestamps[i]);

            bytes memory valueBytes = abi.encode(prices[i]);
            IFeedStructs.Answer memory answer = IFeedStructs.Answer({
                value: valueBytes,
                timestamp: uint64(timestamps[i])
            });

            vm.prank(address(nodeRegistry));
            publicFeed.publish(answer);
        }

        // Only latest round is stored; verify latest and that stale round ids revert
        vm.prank(consumer);
        (
            uint80 latestRoundId,
            int256 latestPrice,
            ,
            uint256 latestUpdatedAt,
            uint80 latestAnsweredInRound
        ) = AggregatorV3Interface(address(publicFeed)).latestRoundData();

        assertEq(latestRoundId, 4);
        assertEq(latestPrice, prices[4]);
        assertEq(latestUpdatedAt, timestamps[4]);
        assertEq(latestAnsweredInRound, 4);

        vm.prank(consumer);
        vm.expectRevert("Invalid round ID");
        AggregatorV3Interface(address(publicFeed)).getRoundData(0);

        vm.prank(consumer);
        (
            uint80 roundId,
            int256 returnedPrice,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = AggregatorV3Interface(address(publicFeed)).getRoundData(4);
        assertEq(roundId, 4);
        assertEq(returnedPrice, prices[4]);
        assertEq(updatedAt, timestamps[4]);
        assertEq(answeredInRound, 4);
    }

    function test_chainlink_gasUsage() public {
        nodeRegistry.setVerificationResult(true);

        // Publish some data
        int256 price = 220000000000;
        bytes memory valueBytes = abi.encode(price);
        IFeedStructs.Answer memory answer = IFeedStructs.Answer({
            value: valueBytes,
            timestamp: uint64(block.timestamp)
        });

        vm.prank(address(nodeRegistry));
        publicFeed.publish(answer);

        // Test gas usage for Chainlink methods
        vm.prank(consumer);
        uint256 gasBefore = gasleft();
        AggregatorV3Interface(address(publicFeed)).latestRoundData();
        uint256 gasUsed = gasBefore - gasleft();

        // Gas usage should be reasonable (less than 100k gas)
        assertTrue(gasUsed < 100000, "latestRoundData gas usage too high");

        vm.prank(consumer);
        gasBefore = gasleft();
        AggregatorV3Interface(address(publicFeed)).getRoundData(0);
        gasUsed = gasBefore - gasleft();

        assertTrue(gasUsed < 100000, "getRoundData gas usage too high");
    }
}
*/
