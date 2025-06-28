// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";

/**
 * @title ParticipationRewardTracker
 * @notice Tracks node participation via bitmaps and distributes rewards accordingly
 * @dev Supports up to 256 nodes via bitmap representation
 */
contract ParticipationRewardTracker is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Maximum number of nodes supported (256 via bitmap)
    uint256 public constant MAX_NODES = 256;

    /// @notice Access control manager for role verification
    IAccessControlManager public immutable accessControlManager;

    /// @notice Reward token (USDC)
    IERC20 public immutable rewardToken;

    /// @notice Total tokens available in the reward pool
    uint256 public rewardPool;

    /// @notice Price per response/signature in reward tokens
    uint256 public pricePerResponse;

    /// @notice Mapping of node address to node index (0-255)
    mapping(address => uint256) public nodeToIndex;

    /// @notice Mapping of node index to node address
    mapping(uint256 => address) public indexToNode;

    /// @notice Array of registered node addresses
    address[] public nodes;

    /// @notice Tracks unpaid rewards for each node
    mapping(address => uint256) public pendingRewards;

    /// @notice Tracks total earned rewards for each node
    mapping(address => uint256) public totalEarnedRewards;

    /// @notice Tracks participation count for each node
    mapping(address => uint256) public participationCount;

    /// @notice Response counter for tracking submissions
    uint256 public responseCounter;

    /// @notice Stores participation bitmaps for each response
    mapping(uint256 => uint256) public responseBitmaps;

    /// @notice Timestamp of each response
    mapping(uint256 => uint256) public responseTimestamps;

    // Events
    event NodeRegistered(address indexed node, uint256 indexed nodeIndex);
    event NodeRemoved(address indexed node, uint256 indexed nodeIndex);
    event ParticipationRecorded(uint256 indexed responseId, uint256 bitmap, uint256 participantCount);
    event RewardsDistributed(address indexed node, uint256 amount);
    event RewardPoolFunded(uint256 amount, uint256 newTotal);
    event PricePerResponseUpdated(uint256 oldPrice, uint256 newPrice);

    // Errors
    error NodeAlreadyRegistered();
    error NodeNotRegistered();
    error MaxNodesReached();
    error InvalidBitmap();
    error InsufficientRewardPool();
    error NoRewardsToClaim();
    error InvalidPricePerResponse();

    constructor(
        IAccessControlManager _accessControlManager,
        IERC20 _rewardToken,
        uint256 _initialPricePerResponse
    ) {
        accessControlManager = _accessControlManager;
        rewardToken = _rewardToken;
        pricePerResponse = _initialPricePerResponse;
    }

    modifier onlyNodeManager() {
        accessControlManager.verifyNodeManager(msg.sender);
        _;
    }

    modifier onlyPriceManager() {
        accessControlManager.verifyPriceManager(msg.sender);
        _;
    }

    modifier onlyFeedManager() {
        accessControlManager.verifyFeedManager(msg.sender);
        _;
    }

    /// @notice Register a new node for participation tracking
    /// @param node Address of the node to register
    function registerNode(address node) external onlyNodeManager {
        if (nodeToIndex[node] != 0 || (nodes.length > 0 && nodes[0] == node)) {
            revert NodeAlreadyRegistered();
        }
        if (nodes.length >= MAX_NODES) {
            revert MaxNodesReached();
        }

        uint256 nodeIndex = nodes.length;
        nodes.push(node);
        nodeToIndex[node] = nodeIndex;
        indexToNode[nodeIndex] = node;

        emit NodeRegistered(node, nodeIndex);
    }

    /// @notice Remove a node from participation tracking
    /// @param node Address of the node to remove
    function removeNode(address node) external onlyNodeManager {
        uint256 nodeIndex = nodeToIndex[node];
        if (nodeIndex == 0 && nodes.length > 0 && nodes[0] != node) {
            revert NodeNotRegistered();
        }

        // Distribute any pending rewards before removal
        if (pendingRewards[node] > 0) {
            _distributeRewards(node);
        }

        // Move last node to the removed node's position
        uint256 lastIndex = nodes.length - 1;
        if (nodeIndex != lastIndex) {
            address lastNode = nodes[lastIndex];
            nodes[nodeIndex] = lastNode;
            nodeToIndex[lastNode] = nodeIndex;
            indexToNode[nodeIndex] = lastNode;
        }

        // Remove the last element
        nodes.pop();
        delete nodeToIndex[node];
        delete indexToNode[lastIndex];

        emit NodeRemoved(node, nodeIndex);
    }

    /// @notice Record participation for a response using a bitmap
    /// @param signersBitmap Bitmap representing which nodes participated (bit i = node at index i)
    /// @dev Each bit position corresponds to a node index. Set bits indicate participation.
    function recordParticipation(uint256 signersBitmap) external onlyFeedManager {
        if (signersBitmap == 0) {
            revert InvalidBitmap();
        }

        uint256 responseId = responseCounter++;
        responseBitmaps[responseId] = signersBitmap;
        responseTimestamps[responseId] = block.timestamp;

        // Count participants and update rewards
        uint256 participantCount = 0;
        uint256 rewardPerParticipant = pricePerResponse;

        // Check if we have enough tokens in the pool
        uint256 bitmap = signersBitmap;
        uint256 tempParticipantCount = 0;
        while (bitmap > 0) {
            if (bitmap & 1 == 1) {
                tempParticipantCount++;
            }
            bitmap >>= 1;
        }

        uint256 totalRewardNeeded = rewardPerParticipant * tempParticipantCount;
        if (rewardPool < totalRewardNeeded) {
            revert InsufficientRewardPool();
        }

        // Update rewards for participants
        bitmap = signersBitmap;
        for (uint256 i = 0; i < nodes.length && bitmap > 0; i++) {
            if (bitmap & 1 == 1) {
                address participant = nodes[i];
                pendingRewards[participant] += rewardPerParticipant;
                totalEarnedRewards[participant] += rewardPerParticipant;
                participationCount[participant]++;
                participantCount++;
            }
            bitmap >>= 1;
        }

        rewardPool -= totalRewardNeeded;

        emit ParticipationRecorded(responseId, signersBitmap, participantCount);
    }

    /// @notice Distribute pending rewards to a specific node
    /// @param node Address of the node to distribute rewards to
    function distributeRewards(address node) external nonReentrant {
        _distributeRewards(node);
    }

    /// @notice Distribute pending rewards to multiple nodes
    /// @param nodeAddresses Array of node addresses to distribute rewards to
    function batchDistributeRewards(address[] calldata nodeAddresses) external nonReentrant {
        for (uint256 i = 0; i < nodeAddresses.length; i++) {
            if (pendingRewards[nodeAddresses[i]] > 0) {
                _distributeRewards(nodeAddresses[i]);
            }
        }
    }

    /// @notice Internal function to distribute rewards to a node
    /// @param node Address of the node
    function _distributeRewards(address node) internal {
        uint256 amount = pendingRewards[node];
        if (amount == 0) {
            revert NoRewardsToClaim();
        }

        pendingRewards[node] = 0;
        rewardToken.safeTransfer(node, amount);

        emit RewardsDistributed(node, amount);
    }

    /// @notice Fund the reward pool with tokens
    /// @param amount Amount of tokens to add to the pool
    function fundRewardPool(uint256 amount) external {
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        rewardPool += amount;

        emit RewardPoolFunded(amount, rewardPool);
    }

    /// @notice Update the price per response
    /// @param newPrice New price per response in reward tokens
    function setPricePerResponse(uint256 newPrice) external onlyPriceManager {
        if (newPrice == 0) {
            revert InvalidPricePerResponse();
        }

        uint256 oldPrice = pricePerResponse;
        pricePerResponse = newPrice;

        emit PricePerResponseUpdated(oldPrice, newPrice);
    }

    /// @notice Get participation bitmap for a specific response
    /// @param responseId ID of the response
    /// @return bitmap Participation bitmap
    /// @return timestamp Timestamp of the response
    function getResponseParticipation(uint256 responseId) 
        external 
        view 
        returns (uint256 bitmap, uint256 timestamp) 
    {
        return (responseBitmaps[responseId], responseTimestamps[responseId]);
    }

    /// @notice Get node information
    /// @param node Address of the node
    /// @return nodeIndex Index of the node
    /// @return pending Pending rewards
    /// @return totalEarned Total earned rewards
    /// @return participations Number of participations
    function getNodeInfo(address node) 
        external 
        view 
        returns (
            uint256 nodeIndex,
            uint256 pending,
            uint256 totalEarned,
            uint256 participations
        ) 
    {
        return (
            nodeToIndex[node],
            pendingRewards[node],
            totalEarnedRewards[node],
            participationCount[node]
        );
    }

    /// @notice Get all registered nodes
    /// @return Array of node addresses
    function getAllNodes() external view returns (address[] memory) {
        return nodes;
    }

    /// @notice Get number of registered nodes
    /// @return count Number of registered nodes
    function getNodeCount() external view returns (uint256 count) {
        return nodes.length;
    }

    /// @notice Check if an address is a registered node
    /// @param node Address to check
    /// @return isRegistered Whether the address is a registered node
    function isRegisteredNode(address node) external view returns (bool isRegistered) {
        return nodeToIndex[node] < nodes.length && nodes[nodeToIndex[node]] == node;
    }

    /// @notice Emergency function to withdraw tokens (only protocol admin)
    /// @param token Token to withdraw
    /// @param amount Amount to withdraw
    /// @param to Recipient address
    function emergencyWithdraw(IERC20 token, uint256 amount, address to) external {
        accessControlManager.verifyProtocolAdmin(msg.sender);
        token.safeTransfer(to, amount);
        
        // If withdrawing reward tokens, update the pool
        if (token == rewardToken) {
            rewardPool = rewardPool > amount ? rewardPool - amount : 0;
        }
    }
} 