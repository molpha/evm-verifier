// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IRewardTracker} from "./interfaces/IRewardTracker.sol";
import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {INodeRegistry} from "./interfaces/INodeRegistry.sol";
import {ITreasury} from "./interfaces/ITreasury.sol";

/**
 * @title RewardTracker
 * @notice Tracks and distributes rewards to nodes based on participation
 * @dev Uses bitmap-based participation tracking for gas efficiency
 */
contract RewardTracker is IRewardTracker, ReentrancyGuard {
    /// @notice Maximum number of nodes (256 for bitmap compatibility)
    uint256 public constant MAX_NODES = 256;

    /// @notice Access control manager for role verification
    IAccessControlManager public immutable accessControlManager;

    /// @notice Node registry contract
    INodeRegistry public immutable nodeRegistry;

    /// @notice Treasury contract for reward payouts
    ITreasury public immutable treasury;

    /// @notice Price per response/signature in reward tokens
    uint256 public pricePerResponse;

    /// @notice Tracks unpaid rewards for each node
    mapping(address => uint256) public pendingRewards;

    /// @notice Global participation bitmaps array
    uint256[] public participationBitmaps;

    /// @notice Track last distributed index for each node
    mapping(address node => uint256) public nodeLastDistributedIndex;

    constructor(
        IAccessControlManager _accessControlManager,
        INodeRegistry _nodeRegistry,
        ITreasury _treasury,
        uint256 _initialPricePerResponse
    ) {
        accessControlManager = _accessControlManager;
        nodeRegistry = _nodeRegistry;
        treasury = _treasury;
        pricePerResponse = _initialPricePerResponse;
    }

    modifier onlyNodeRegistry() {
        accessControlManager.verifyNodeRegistry(msg.sender);
        _;
    }

    /// @notice Record participation using a bitmap
    /// @param signersBitmap Bitmap representing which nodes participated (0-based positions)
    /// @return index The index in the bitmap array where this participation was stored
    function recordParticipation(
        uint256 signersBitmap
    ) external onlyNodeRegistry returns (uint256 index) {
        if (signersBitmap == 0) revert InvalidBitmap();

        // Add bitmap to the global array
        index = participationBitmaps.length;
        participationBitmaps.push(signersBitmap);

        emit ParticipationRecorded(index, signersBitmap);
    }

    /// @notice Distribute rewards for a node with batch size limit
    /// @param node Node address to distribute rewards to
    /// @param maxBitmapsToProcess Maximum number of bitmaps to process in this call
    /// @return processed Number of bitmaps processed
    /// @return remaining Number of bitmaps remaining to process
    function distributeReward(
        address node,
        uint256 maxBitmapsToProcess
    ) external returns (uint256 processed, uint256 remaining) {
        if (maxBitmapsToProcess == 0) revert InvalidBatchSize();

        // Get node index from registry (will revert if not a valid node)
        if (!nodeRegistry.isNode(node)) revert NotNode(node);

        uint256 lastDistributed = nodeLastDistributedIndex[node];
        uint256 totalBitmaps = participationBitmaps.length;

        // Calculate how many to process
        uint256 unprocessed = totalBitmaps - lastDistributed;
        if (unprocessed == 0) revert NoNewParticipations();

        uint256 toProcess = unprocessed > maxBitmapsToProcess
            ? maxBitmapsToProcess
            : unprocessed;

        // Get node's bitmap position (requires knowing the node's index)
        // This is a limitation - we need a way to get node index from registry
        uint256 participationCount = _countParticipations(node, lastDistributed, lastDistributed + toProcess);

        // Update state
        if (participationCount > 0) {
            pendingRewards[node] += participationCount * pricePerResponse;
        }

        nodeLastDistributedIndex[node] = lastDistributed + toProcess;

        // Return processing info
        processed = toProcess;
        remaining = totalBitmaps - (lastDistributed + toProcess);

        emit RewardDistributed(
            node,
            lastDistributed,
            lastDistributed + toProcess,
            participationCount * pricePerResponse
        );
    }

    /// @notice Claim pending rewards for the calling node
    function claimRewards() external nonReentrant {
        _claimRewards(msg.sender);
    }

    /// @notice Claim rewards for a specific node (only by feeds manager)
    /// @param node Node address to claim rewards for
    function claimRewardsFor(
        address node
    ) external onlyNodeRegistry nonReentrant {
        _claimRewards(node);
    }

    /// @notice Internal function to claim rewards
    /// @param node Address of the node claiming rewards
    function _claimRewards(address node) internal {
        uint256 amount = pendingRewards[node];
        if (amount == 0) revert NoRewardsToClaim();

        pendingRewards[node] = 0;
        
        // Request payout from treasury
        treasury.payReward(node, amount);

        emit RewardsClaimed(node, amount);
    }

    /// @notice Update the price per response
    /// @param newPrice New price per response in reward tokens
    function setPricePerResponse(uint256 newPrice) external onlyNodeRegistry {
        if (newPrice == 0) revert InvalidPricePerResponse();

        uint256 oldPrice = pricePerResponse;
        pricePerResponse = newPrice;

        emit PricePerResponseUpdated(oldPrice, newPrice);
    }

    /// @notice Get total number of participation bitmaps recorded
    /// @return Total number of bitmaps
    function getTotalParticipations() external view returns (uint256) {
        return participationBitmaps.length;
    }

    /// @notice Get participation bitmap at specific index
    /// @param index Index in the bitmap array
    /// @return bitmap Participation bitmap at the specified index
    function getParticipationBitmap(
        uint256 index
    ) external view returns (uint256 bitmap) {
        if (index >= participationBitmaps.length) revert InvalidIndex(index);
        return participationBitmaps[index];
    }

    /// @notice Get multiple participation bitmaps in a range
    /// @param from Start index (inclusive)
    /// @param to End index (exclusive)
    /// @return bitmaps Array of participation bitmaps
    function getParticipationBitmaps(
        uint256 from,
        uint256 to
    ) external view returns (uint256[] memory bitmaps) {
        if (to > participationBitmaps.length) revert InvalidIndex(to);
        if (from >= to) revert InvalidIndex(from);

        bitmaps = new uint256[](to - from);
        for (uint256 i = 0; i < bitmaps.length; i++) {
            bitmaps[i] = participationBitmaps[from + i];
        }
    }

    /// @notice Get node reward information
    /// @param node Address of the node
    /// @return pending Pending rewards
    /// @return lastProcessedIndex Last processed participation index
    /// @return unprocessedCount Number of unprocessed participations
    function getNodeRewardInfo(
        address node
    )
        external
        view
        returns (
            uint256 pending,
            uint256 lastProcessedIndex,
            uint256 unprocessedCount
        )
    {
        pending = pendingRewards[node];
        lastProcessedIndex = nodeLastDistributedIndex[node];
        unprocessedCount = participationBitmaps.length - lastProcessedIndex;
    }

    /// @notice Count participations for a node in a range of bitmaps
    /// @param node Node address
    /// @param fromIndex Start index (inclusive)
    /// @param toIndex End index (exclusive)
    /// @return count Number of participations
    function _countParticipations(
        address node,
        uint256 fromIndex,
        uint256 toIndex
    ) internal view returns (uint256 count) {
        // Get node index from registry (1-based)
        uint256 nodeIndex = nodeRegistry.getNodeIndex(node);
        if (nodeIndex == 0) revert NotNode(node);
        
        // Convert to 0-based bitmap position
        uint256 bitmapPosition = nodeIndex - 1;
        
        // Count participations
        for (uint256 i = fromIndex; i < toIndex; i++) {
            if ((participationBitmaps[i] >> bitmapPosition) & 1 == 1) {
                count++;
            }
        }
    }
} 