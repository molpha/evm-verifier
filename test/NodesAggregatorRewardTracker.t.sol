// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {NodesAggregatorRewardTracker} from "../src/NodesAggregatorRewardTracker.sol";
import {FeedPricingManager} from "../src/FeedPricingManager.sol";
import {MockAccessControlManager} from "./mocks/MockAccessControlManager.sol";
import {MockedUSDC} from "../src/mocks/MockedUSDC.sol";
import {LibSecp256k1} from "../src/libs/LibSecp256k1.sol";
import {INodesAggregator} from "../src/interfaces/INodesAggregator.sol";

contract NodesAggregatorRewardTrackerTest is Test {
    NodesAggregatorRewardTracker public tracker;
    FeedPricingManager public pricingManager;
    MockAccessControlManager public accessControlManager;
    MockedUSDC public usdc;

    address public admin = makeAddr("admin");
    address public nodesManager = makeAddr("nodesManager");
    address public feedsManager = makeAddr("feedsManager");
    address public priceManager = makeAddr("priceManager");
    
    address public node1 = makeAddr("node1");
    address public node2 = makeAddr("node2");
    address public node3 = makeAddr("node3");
    address public node4 = makeAddr("node4");

    uint256 public constant INITIAL_PRICE_PER_RESPONSE = 1e4; // $0.01 in USDC (6 decimals)
    uint256 public constant INITIAL_FUNDING = 1000e6; // 1000 USDC

    // Sample public keys for testing
    LibSecp256k1.Point public pubkey1;
    LibSecp256k1.Point public pubkey2;
    LibSecp256k1.Point public pubkey3;
    LibSecp256k1.Point public pubkey4;

    function setUp() public {
        // Deploy contracts
        accessControlManager = new MockAccessControlManager();
        pricingManager = new FeedPricingManager(accessControlManager);
        usdc = new MockedUSDC();
        
        tracker = new NodesAggregatorRewardTracker(
            admin,
            accessControlManager,
            pricingManager,
            IERC20(address(usdc)),
            INITIAL_PRICE_PER_RESPONSE
        );

        // Setup roles
        accessControlManager.setNodesManager(nodesManager);
        accessControlManager.setFeedsManager(feedsManager);
        accessControlManager.setPriceManager(priceManager);
        accessControlManager.setProtocolAdmin(admin);

        // Fund the tracker by transferring tokens directly
        usdc.mint(address(tracker), INITIAL_FUNDING);

        // Create sample public keys (using mock data for testing)
        pubkey1 = LibSecp256k1.Point({x: 1, y: 2});
        pubkey2 = LibSecp256k1.Point({x: 3, y: 4});
        pubkey3 = LibSecp256k1.Point({x: 5, y: 6});
        pubkey4 = LibSecp256k1.Point({x: 7, y: 8});

        // Mock the toAddress function behavior
        vm.mockCall(
            address(0),
            abi.encodeWithSelector(LibSecp256k1.toAddress.selector),
            abi.encode(node1)
        );
    }

    function testConstructor() public {
        assertEq(address(tracker.accessControlManager()), address(accessControlManager));
        assertEq(address(tracker.feedPricingManager()), address(pricingManager));
        assertEq(address(tracker.rewardToken()), address(usdc));
        assertEq(tracker.pricePerResponse(), INITIAL_PRICE_PER_RESPONSE);
        assertEq(tracker.getTotalNodes(), 0);
    }

    function testAddNode() public {
        vm.startPrank(nodesManager);
        
        // Mock the public key to address conversion
        vm.mockCall(
            address(pubkey1),
            abi.encodeWithSelector(LibSecp256k1.toAddress.selector),
            abi.encode(node1)
        );
        
        vm.expectEmit(true, true, true, false);
        emit LogNodeAdded(node1, 1, address(0)); // newPointer will be different
        
        tracker.addNode(pubkey1);
        
        assertTrue(tracker.isNode(node1));
        assertEq(tracker.nodeIndexes(node1), 1);
        assertEq(tracker.getTotalNodes(), 1);
        
        vm.stopPrank();
    }

    function testAddNodeRevertIfAlreadyAdded() public {
        vm.startPrank(nodesManager);
        
        // Mock the public key to address conversion
        vm.mockCall(
            address(pubkey1),
            abi.encodeWithSelector(LibSecp256k1.toAddress.selector),
            abi.encode(node1)
        );
        
        tracker.addNode(pubkey1);
        
        vm.expectRevert(abi.encodeWithSelector(NodesAggregatorRewardTracker.NodeAlreadyAdded.selector, node1));
        tracker.addNode(pubkey1);
        
        vm.stopPrank();
    }

    function testAddNodeRevertIfZeroPoint() public {
        vm.startPrank(nodesManager);
        
        LibSecp256k1.Point memory zeroPoint = LibSecp256k1.Point({x: 0, y: 0});
        
        vm.expectRevert(NodesAggregatorRewardTracker.InvalidPublicKey.selector);
        tracker.addNode(zeroPoint);
        
        vm.stopPrank();
    }

    function testRemoveNode() public {
        // First add a node
        vm.startPrank(nodesManager);
        
        vm.mockCall(
            address(pubkey1),
            abi.encodeWithSelector(LibSecp256k1.toAddress.selector),
            abi.encode(node1)
        );
        
        tracker.addNode(pubkey1);
        
        vm.expectEmit(true, true, true, false);
        emit LogNodeRemoved(node1, 1, address(0));
        
        tracker.removeNode(node1);
        
        assertFalse(tracker.isNode(node1));
        assertEq(tracker.nodeIndexes(node1), 0);
        assertEq(tracker.getTotalNodes(), 0);
        
        vm.stopPrank();
    }

    function testRemoveNodeWithPendingRewards() public {
        // Add node and give it some rewards
        vm.startPrank(nodesManager);
        
        vm.mockCall(
            address(pubkey1),
            abi.encodeWithSelector(LibSecp256k1.toAddress.selector),
            abi.encode(node1)
        );
        
        tracker.addNode(pubkey1);
        vm.stopPrank();

        // Record participation to give rewards
        vm.prank(feedsManager);
        tracker.recordParticipation(1); // bitmap: 1 = first node participates

        // Check pending rewards
        assertGt(tracker.pendingRewards(node1), 0);
        
        uint256 initialBalance = usdc.balanceOf(node1);
        
        // Remove node (should auto-distribute rewards)
        vm.prank(nodesManager);
        tracker.removeNode(node1);
        
        assertEq(tracker.pendingRewards(node1), 0);
        assertEq(usdc.balanceOf(node1), initialBalance + INITIAL_PRICE_PER_RESPONSE);
    }

    function testRecordParticipationBitmap() public {
        // Add some nodes first
        _addTestNodes();
        
        vm.startPrank(feedsManager);
        
        // Bitmap: 0b1011 = 11 (nodes at positions 0, 1, 3 participate)
        uint256 bitmap = 11;
        
        vm.expectEmit(true, false, false, true);
        emit ParticipationRecorded(0, bitmap, 3);
        
        tracker.recordParticipation(bitmap);
        
        (uint256 storedBitmap, uint256 timestamp) = tracker.getResponseParticipation(0);
        assertEq(storedBitmap, bitmap);
        assertEq(timestamp, block.timestamp);
        
        vm.stopPrank();
    }

    function testRecordParticipationFromSignature() public {
        // Add some nodes first
        _addTestNodes();
        
        vm.startPrank(feedsManager);
        
        // Test with bitmap directly (nodes at positions 0 and 2 participate)
        // Binary: 0101 = 5
        uint256 bitmap = 5;
        
        vm.expectEmit(true, false, false, true);
        emit ParticipationRecorded(0, bitmap, 2);
        
        tracker.recordParticipationFromSignature(bitmap);
        
        vm.stopPrank();
    }

    function testDistributeRewards() public {
        _addTestNodes();
        
        // Record participation
        vm.prank(feedsManager);
        tracker.recordParticipation(1); // Only first node participates
        
        uint256 initialBalance = usdc.balanceOf(node1);
        
        vm.expectEmit(true, false, false, true);
        emit RewardsDistributed(node1, INITIAL_PRICE_PER_RESPONSE);
        
        tracker.distributeRewards(node1);
        
        assertEq(usdc.balanceOf(node1), initialBalance + INITIAL_PRICE_PER_RESPONSE);
        assertEq(tracker.pendingRewards(node1), 0);
    }

    function testBatchDistributeRewards() public {
        _addTestNodes();
        
        // Record participation for multiple nodes
        vm.prank(feedsManager);
        tracker.recordParticipation(3); // First two nodes participate (binary: 11)
        
        uint256 initialBalance1 = usdc.balanceOf(node1);
        uint256 initialBalance2 = usdc.balanceOf(node2);
        
        address[] memory nodes = new address[](2);
        nodes[0] = node1;
        nodes[1] = node2;
        
        tracker.batchDistributeRewards(nodes);
        
        assertEq(usdc.balanceOf(node1), initialBalance1 + INITIAL_PRICE_PER_RESPONSE);
        assertEq(usdc.balanceOf(node2), initialBalance2 + INITIAL_PRICE_PER_RESPONSE);
    }



    function testSetPricePerResponse() public {
        uint256 newPrice = 2e4; // $0.02
        
        vm.startPrank(priceManager);
        
        vm.expectEmit(false, false, false, true);
        emit PricePerResponseUpdated(INITIAL_PRICE_PER_RESPONSE, newPrice);
        
        tracker.setPricePerResponse(newPrice);
        
        assertEq(tracker.pricePerResponse(), newPrice);
        
        vm.stopPrank();
    }

    function testGetNodeInfo() public {
        _addTestNodes();
        
        // Record participation
        vm.prank(feedsManager);
        tracker.recordParticipation(1); // Only first node participates
        
        (uint256 nodeIndex, uint256 pending, uint256 totalEarned, uint256 participations) = 
            tracker.getNodeInfo(node1);
        
        assertEq(nodeIndex, 1); // 1-based indexing
        assertEq(pending, INITIAL_PRICE_PER_RESPONSE);
        assertEq(totalEarned, INITIAL_PRICE_PER_RESPONSE);
        assertEq(participations, 1);
    }

    function testGetAllNodes() public {
        _addTestNodes();
        
        address[] memory allNodes = tracker.getAllNodes();
        
        assertEq(allNodes.length, 4);
        // Note: The exact order might depend on the mock implementation
    }

    function testEmergencyWithdraw() public {
        uint256 withdrawAmount = 100e6;
        uint256 initialBalance = usdc.balanceOf(admin);
        
        vm.startPrank(admin);
        
        tracker.emergencyWithdraw(IERC20(address(usdc)), withdrawAmount, admin);
        
        assertEq(usdc.balanceOf(admin), initialBalance + withdrawAmount);
        
        vm.stopPrank();
    }



    function testBitmapIndexConversion() public {
        _addTestNodes();
        
        vm.startPrank(feedsManager);
        
        // Test bitmap position 0 corresponds to node index 1
        tracker.recordParticipation(1); // bitmap position 0
        
        // Node at index 1 should have rewards
        assertEq(tracker.pendingRewards(node1), INITIAL_PRICE_PER_RESPONSE);
        assertEq(tracker.pendingRewards(node2), 0);
        assertEq(tracker.pendingRewards(node3), 0);
        assertEq(tracker.pendingRewards(node4), 0);
        
        vm.stopPrank();
    }

    // Helper function to add test nodes
    function _addTestNodes() internal {
        vm.startPrank(nodesManager);
        
        // Mock address conversions for all test nodes
        vm.mockCall(
            address(pubkey1),
            abi.encodeWithSelector(LibSecp256k1.toAddress.selector),
            abi.encode(node1)
        );
        vm.mockCall(
            address(pubkey2),
            abi.encodeWithSelector(LibSecp256k1.toAddress.selector),
            abi.encode(node2)
        );
        vm.mockCall(
            address(pubkey3),
            abi.encodeWithSelector(LibSecp256k1.toAddress.selector),
            abi.encode(node3)
        );
        vm.mockCall(
            address(pubkey4),
            abi.encodeWithSelector(LibSecp256k1.toAddress.selector),
            abi.encode(node4)
        );
        
        tracker.addNode(pubkey1);
        tracker.addNode(pubkey2);
        tracker.addNode(pubkey3);
        tracker.addNode(pubkey4);
        
        vm.stopPrank();
    }

    // Events for testing
    event LogNodeAdded(address indexed node, uint256 indexed index, address indexed newPointer);
    event LogNodeRemoved(address indexed node, uint256 indexed index, address indexed newPointer);
    event ParticipationRecorded(uint256 indexed responseId, uint256 bitmap, uint256 participantCount);
    event RewardsDistributed(address indexed node, uint256 amount);
    event PricePerResponseUpdated(uint256 oldPrice, uint256 newPrice);
} 