// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title IRewardTracker
/// @notice Interface for tracking and distributing rewards to nodes based on participation
interface IRewardTracker {
    // Events
    event ParticipationRecorded(uint256 indexed index, uint256 bitmap);
    event RewardDistributed(
        address indexed node,
        uint256 fromIndex,
        uint256 toIndex,
        uint256 amount
    );
    event RewardsClaimed(address indexed node, uint256 amount);
    event PricePerResponseUpdated(uint256 oldPrice, uint256 newPrice);

    /// @notice Record participation using a bitmap
    /// @param signersBitmap Bitmap representing which nodes participated (0-based positions)
    /// @return index The index in the bitmap array where this participation was stored
    function recordParticipation(uint256 signersBitmap) external returns (uint256 index);

    /// @notice Distribute rewards for a node with batch size limit
    /// @param node Node address to distribute rewards to
    /// @param maxBitmapsToProcess Maximum number of bitmaps to process in this call
    /// @return processed Number of bitmaps processed
    /// @return remaining Number of bitmaps remaining to process
    function distributeReward(
        address node,
        uint256 maxBitmapsToProcess
    ) external returns (uint256 processed, uint256 remaining);

    /// @notice Claim pending rewards for the calling node
    function claimRewards() external;

    /// @notice Claim rewards for a specific node (privileged function)
    /// @param node Node address to claim rewards for
    function claimRewardsFor(address node) external;

    /// @notice Update the price per response
    /// @param newPrice New price per response in reward tokens
    function setPricePerResponse(uint256 newPrice) external;

    /// @notice Get total number of participation bitmaps recorded
    /// @return Total number of bitmaps
    function getTotalParticipations() external view returns (uint256);

    /// @notice Get participation bitmap at specific index
    /// @param index Index in the bitmap array
    /// @return bitmap Participation bitmap at the specified index
    function getParticipationBitmap(uint256 index) external view returns (uint256 bitmap);

    /// @notice Get multiple participation bitmaps in a range
    /// @param from Start index (inclusive)
    /// @param to End index (exclusive)
    /// @return bitmaps Array of participation bitmaps
    function getParticipationBitmaps(
        uint256 from,
        uint256 to
    ) external view returns (uint256[] memory bitmaps);

    /// @notice Get node reward information
    /// @param node Address of the node
    /// @return pending Pending rewards
    /// @return lastProcessedIndex Last processed participation index
    /// @return unprocessedCount Number of unprocessed participations
    function getNodeRewardInfo(address node) external view returns (
        uint256 pending,
        uint256 lastProcessedIndex,
        uint256 unprocessedCount
    );

    /// @notice Get the price per response
    /// @return Current price per response
    function pricePerResponse() external view returns (uint256);

    /// @notice Get pending rewards for a node
    /// @param node Node address
    /// @return Amount of pending rewards
    function pendingRewards(address node) external view returns (uint256);

    /// @notice Get last distributed index for a node
    /// @param node Node address
    /// @return Last distributed index
    function nodeLastDistributedIndex(address node) external view returns (uint256);
} 