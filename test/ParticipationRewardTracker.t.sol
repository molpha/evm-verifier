// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ParticipationRewardTracker} from "../src/ParticipationRewardTracker.sol";
import {MockAccessControlManager} from "./mocks/MockAccessControlManager.sol";
import {MockedUSDC} from "../src/mocks/MockedUSDC.sol";

contract ParticipationRewardTrackerTest is Test {
    ParticipationRewardTracker public tracker;
    MockAccessControlManager public accessControlManager;
    MockedUSDC public usdc;

    address public admin = makeAddr("admin");
    address public nodeManager = makeAddr("nodeManager");
    address public feedManager = makeAddr("feedManager");
    address public priceManager = makeAddr("priceManager");
    
    address public node1 = makeAddr("node1");
    address public node2 = makeAddr("node2");
    address public node3 = makeAddr("node3");
    address public node4 = makeAddr("node4");

    uint256 public constant INITIAL_PRICE_PER_RESPONSE = 1e4; // $0.01 in USDC (6 decimals)
    uint256 public constant INITIAL_FUNDING = 1000e6; // 1000 USDC

    function setUp() public {
        // Deploy contracts
        accessControlManager = new MockAccessControlManager(admin);
        usdc = new MockedUSDC();
        
        tracker = new ParticipationRewardTracker(
            accessControlManager,
            IERC20(address(usdc)),
            INITIAL_PRICE_PER_RESPONSE
        );

        // Setup roles
        accessControlManager.setNodeManager(nodeManager);
        accessControlManager.setFeedManager(feedManager);
        accessControlManager.setPriceManager(priceManager);
        accessControlManager.setProtocolAdmin(admin);

        // Fund the tracker
        usdc.mint(address(this), INITIAL_FUNDING);
        usdc.approve(address(tracker), INITIAL_FUNDING);
        tracker.fundRewardPool(INITIAL_FUNDING);

        // Register some nodes
        vm.startPrank(nodeManager);
        tracker.registerNode(node1);
        tracker.registerNode(node2);
        tracker.registerNode(node3);
        tracker.registerNode(node4);
        vm.stopPrank();
    }

    function testConstructor() public {
        assertEq(address(tracker.accessControlManager()), address(accessControlManager));
        assertEq(address(tracker.rewardToken()), address(usdc));
        assertEq(tracker.pricePerResponse(), INITIAL_PRICE_PER_RESPONSE);
        assertEq(tracker.rewardPool(), INITIAL_FUNDING);
    }

    function testRegisterNode() public {
        vm.startPrank(nodeManager);
        
        address newNode = makeAddr("newNode");
        
        vm.expectEmit(true, true, false, true);
        emit NodeRegistered(newNode, 4);
        
        tracker.registerNode(newNode);
        
        assertTrue(tracker.isRegisteredNode(newNode));
        assertEq(tracker.nodeToIndex(newNode), 4);
        assertEq(tracker.indexToNode(4), newNode);
        assertEq(tracker.getNodeCount(), 5);
        
        vm.stopPrank();
    }

    function testRegisterNodeRevertIfAlreadyRegistered() public {
        vm.startPrank(nodeManager);
        
        vm.expectRevert(ParticipationRewardTracker.NodeAlreadyRegistered.selector);
        tracker.registerNode(node1);
        
        vm.stopPrank();
    }

    function testRegisterNodeRevertIfMaxNodesReached() public {
        vm.startPrank(nodeManager);
        
        // Register nodes up to MAX_NODES (256)
        for (uint256 i = 4; i < 256; i++) {
            tracker.registerNode(makeAddr(string(abi.encodePacked("node", i))));
        }
        
        vm.expectRevert(ParticipationRewardTracker.MaxNodesReached.selector);
        tracker.registerNode(makeAddr("overflow"));
        
        vm.stopPrank();
    }

    function testRemoveNode() public {
        vm.startPrank(nodeManager);
        
        vm.expectEmit(true, true, false, true);
        emit NodeRemoved(node2, 1);
        
        tracker.removeNode(node2);
        
        assertFalse(tracker.isRegisteredNode(node2));
        assertEq(tracker.getNodeCount(), 3);
        
        // node4 should have moved to index 1
        assertEq(tracker.nodeToIndex(node4), 1);
        assertEq(tracker.indexToNode(1), node4);
        
        vm.stopPrank();
    }

    function testRemoveNodeRevertIfNotRegistered() public {
        vm.startPrank(nodeManager);
        
        address nonExistentNode = makeAddr("nonExistent");
        
        vm.expectRevert(ParticipationRewardTracker.NodeNotRegistered.selector);
        tracker.removeNode(nonExistentNode);
        
        vm.stopPrank();
    }

    function testRecordParticipation() public {
        vm.startPrank(feedManager);
        
        // Bitmap: nodes 0, 1, 3 participated (binary: 1011 = 11)
        uint256 bitmap = 11;
        
        vm.expectEmit(true, false, false, true);
        emit ParticipationRecorded(0, bitmap, 3);
        
        tracker.recordParticipation(bitmap);
        
        (uint256 storedBitmap, uint256 timestamp) = tracker.getResponseParticipation(0);
        assertEq(storedBitmap, bitmap);
        assertEq(timestamp, block.timestamp);
        
        // Check rewards were updated
        assertEq(tracker.pendingRewards(node1), INITIAL_PRICE_PER_RESPONSE); // index 0
        assertEq(tracker.pendingRewards(node2), INITIAL_PRICE_PER_RESPONSE); // index 1
        assertEq(tracker.pendingRewards(node3), 0); // index 2 - didn't participate
        assertEq(tracker.pendingRewards(node4), INITIAL_PRICE_PER_RESPONSE); // index 3
        
        // Check participation counts
        assertEq(tracker.participationCount(node1), 1);
        assertEq(tracker.participationCount(node2), 1);
        assertEq(tracker.participationCount(node3), 0);
        assertEq(tracker.participationCount(node4), 1);
        
        vm.stopPrank();
    }

    function testRecordParticipationRevertInvalidBitmap() public {
        vm.startPrank(feedManager);
        
        vm.expectRevert(ParticipationRewardTracker.InvalidBitmap.selector);
        tracker.recordParticipation(0);
        
        vm.stopPrank();
    }

    function testRecordParticipationRevertInsufficientPool() public {
        // Drain the reward pool
        vm.prank(admin);
        tracker.emergencyWithdraw(IERC20(address(usdc)), INITIAL_FUNDING, admin);
        
        vm.startPrank(feedManager);
        
        vm.expectRevert(ParticipationRewardTracker.InsufficientRewardPool.selector);
        tracker.recordParticipation(1); // Even 1 participant should fail
        
        vm.stopPrank();
    }

    function testDistributeRewards() public {
        // Record participation first
        vm.prank(feedManager);
        tracker.recordParticipation(1); // Only node1 participates
        
        uint256 initialBalance = usdc.balanceOf(node1);
        
        vm.expectEmit(true, false, false, true);
        emit RewardsDistributed(node1, INITIAL_PRICE_PER_RESPONSE);
        
        tracker.distributeRewards(node1);
        
        assertEq(usdc.balanceOf(node1), initialBalance + INITIAL_PRICE_PER_RESPONSE);
        assertEq(tracker.pendingRewards(node1), 0);
    }

    function testDistributeRewardsRevertNoRewards() public {
        vm.expectRevert(ParticipationRewardTracker.NoRewardsToClaim.selector);
        tracker.distributeRewards(node1);
    }

    function testBatchDistributeRewards() public {
        // Record participation
        vm.prank(feedManager);
        tracker.recordParticipation(3); // nodes 0 and 1 participate (binary: 11)
        
        uint256 initialBalance1 = usdc.balanceOf(node1);
        uint256 initialBalance2 = usdc.balanceOf(node2);
        
        address[] memory nodes = new address[](2);
        nodes[0] = node1;
        nodes[1] = node2;
        
        tracker.batchDistributeRewards(nodes);
        
        assertEq(usdc.balanceOf(node1), initialBalance1 + INITIAL_PRICE_PER_RESPONSE);
        assertEq(usdc.balanceOf(node2), initialBalance2 + INITIAL_PRICE_PER_RESPONSE);
        assertEq(tracker.pendingRewards(node1), 0);
        assertEq(tracker.pendingRewards(node2), 0);
    }

    function testFundRewardPool() public {
        uint256 additionalFunding = 500e6;
        usdc.mint(address(this), additionalFunding);
        usdc.approve(address(tracker), additionalFunding);
        
        vm.expectEmit(false, false, false, true);
        emit RewardPoolFunded(additionalFunding, INITIAL_FUNDING + additionalFunding);
        
        tracker.fundRewardPool(additionalFunding);
        
        assertEq(tracker.rewardPool(), INITIAL_FUNDING + additionalFunding);
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

    function testSetPricePerResponseRevertInvalidPrice() public {
        vm.startPrank(priceManager);
        
        vm.expectRevert(ParticipationRewardTracker.InvalidPricePerResponse.selector);
        tracker.setPricePerResponse(0);
        
        vm.stopPrank();
    }

    function testGetNodeInfo() public {
        // Record participation and rewards
        vm.prank(feedManager);
        tracker.recordParticipation(1); // Only node1 participates
        
        (uint256 nodeIndex, uint256 pending, uint256 totalEarned, uint256 participations) = 
            tracker.getNodeInfo(node1);
        
        assertEq(nodeIndex, 0);
        assertEq(pending, INITIAL_PRICE_PER_RESPONSE);
        assertEq(totalEarned, INITIAL_PRICE_PER_RESPONSE);
        assertEq(participations, 1);
    }

    function testGetAllNodes() public {
        address[] memory allNodes = tracker.getAllNodes();
        
        assertEq(allNodes.length, 4);
        assertEq(allNodes[0], node1);
        assertEq(allNodes[1], node2);
        assertEq(allNodes[2], node3);
        assertEq(allNodes[3], node4);
    }

    function testEmergencyWithdraw() public {
        uint256 withdrawAmount = 100e6;
        uint256 initialBalance = usdc.balanceOf(admin);
        
        vm.startPrank(admin);
        
        tracker.emergencyWithdraw(IERC20(address(usdc)), withdrawAmount, admin);
        
        assertEq(usdc.balanceOf(admin), initialBalance + withdrawAmount);
        assertEq(tracker.rewardPool(), INITIAL_FUNDING - withdrawAmount);
        
        vm.stopPrank();
    }

    function testComplexParticipationScenario() public {
        vm.startPrank(feedManager);
        
        // Response 1: nodes 0, 2 participate (binary: 0101 = 5)
        tracker.recordParticipation(5);
        
        // Response 2: nodes 1, 3 participate (binary: 1010 = 10)
        tracker.recordParticipation(10);
        
        // Response 3: all nodes participate (binary: 1111 = 15)
        tracker.recordParticipation(15);
        
        vm.stopPrank();
        
        // Check final states
        assertEq(tracker.pendingRewards(node1), INITIAL_PRICE_PER_RESPONSE * 2); // responses 1 and 3
        assertEq(tracker.pendingRewards(node2), INITIAL_PRICE_PER_RESPONSE * 2); // responses 2 and 3
        assertEq(tracker.pendingRewards(node3), INITIAL_PRICE_PER_RESPONSE * 2); // responses 1 and 3
        assertEq(tracker.pendingRewards(node4), INITIAL_PRICE_PER_RESPONSE * 2); // responses 2 and 3
        
        assertEq(tracker.participationCount(node1), 2);
        assertEq(tracker.participationCount(node2), 2);
        assertEq(tracker.participationCount(node3), 2);
        assertEq(tracker.participationCount(node4), 2);
        
        assertEq(tracker.responseCounter(), 3);
    }

    // Events for testing
    event NodeRegistered(address indexed node, uint256 indexed nodeIndex);
    event NodeRemoved(address indexed node, uint256 indexed nodeIndex);
    event ParticipationRecorded(uint256 indexed responseId, uint256 bitmap, uint256 participantCount);
    event RewardsDistributed(address indexed node, uint256 amount);
    event RewardPoolFunded(uint256 amount, uint256 newTotal);
    event PricePerResponseUpdated(uint256 oldPrice, uint256 newPrice);
} 