// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {LibSecp256k1} from "./libs/LibSecp256k1.sol";
import {LibSchnorr} from "./libs/LibSchnorr.sol";
import {SchnorrSetVerifierLib} from "./libs/SchnorrSetVerifierLib.sol";
import {INodeAggregator} from "./interfaces/INodeAggregator.sol";
import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";

/**
 * @title NodeAggregatorRewardTracker
 * @notice Combined contract for node management, Schnorr signature verification, and reward tracking
 * @dev Supports up to 256 nodes with efficient SSTORE2 storage and bitmap-based participation tracking
 */
contract NodeAggregatorRewardTracker is INodeAggregator, ReentrancyGuard {
    using LibSchnorr for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.JacobianPoint;
    using SchnorrSetVerifierLib for bytes;
    using SafeERC20 for IERC20;

    /// @notice Maximum number of allowed nodes (256 for bitmap compatibility)
    uint256 public constant MAX_NODES = 256;

    /// @notice Start index for 1-based indexing (index 0 is reserved)
    uint256 public constant START_INDEX = 1;

    /// @notice Access control manager for role verification
    IAccessControlManager public immutable accessControlManager;

    /// @notice Reward token (USDC)
    IERC20 public immutable rewardToken;

    /// @notice Price per response/signature in reward tokens
    uint256 public pricePerResponse;

    /// @notice Mapping of node addresses to their indexes (1-based)
    mapping(address node => uint256 index) public nodeIndexes;

    /// @notice Pointer to nodes array stored with SSTORE2
    address public pointer;

    /// @notice Tracks unpaid rewards for each node
    mapping(address => uint256) public pendingRewards;

    /// @notice Feed participation bitmaps - feed address maps to array of bitmaps
    mapping(address => uint256[]) public feedParticipation;

    /// @notice Track last distributed index for each node per feed
    mapping(address feed => mapping(address node => uint256 lastDistributedIndex))
        public nodeLastDistributedIndex;

    // Events for new reward flow
    event FeedParticipationRecorded(
        address indexed feed,
        uint256 bitmap
    );
    event RewardDistributed(
        address indexed feed,
        address indexed node,
        uint256 fromIndex,
        uint256 toIndex,
        uint256 amount
    );
    event RewardsClaimed(address indexed node, uint256 amount);
    event PricePerResponseUpdated(uint256 oldPrice, uint256 newPrice);

    // Errors for new reward flow
    error InvalidBitmap();
    error NoRewardsToClaim();
    error InvalidPricePerResponse();
    error InvalidFeed();
    error NodeNotInFeed();
    error NoNewParticipations();

    constructor(
        address initialOwner,
        IAccessControlManager _accessControlManager,
        IERC20 _rewardToken,
        uint256 _initialPricePerResponse
    ) {
        // Initialize SSTORE2 with empty array (index 0 reserved)
        LibSecp256k1.Point[] memory pubKeys = new LibSecp256k1.Point[](
            START_INDEX
        );
        pointer = SSTORE2.write(abi.encode(pubKeys));

        // Initialize reward tracking
        accessControlManager = _accessControlManager;
        rewardToken = _rewardToken;
        pricePerResponse = _initialPricePerResponse;
    }

    modifier onlyNodeManager() {
        accessControlManager.verifyNodeManager(msg.sender);
        _;
    }

    modifier onlyFeedManager() {
        accessControlManager.verifyFeedManager(msg.sender);
        _;
    }

    /// @notice Add a new node to the aggregator group
    /// @param pubkey Public key of the node
    function addNode(
        LibSecp256k1.Point memory pubkey
    ) external override onlyNodeManager {
        if (pubkey.isZeroPoint()) revert InvalidPublicKey();

        address node = pubkey.toAddress();
        if (node == address(0)) revert ZeroAddress();

        bytes memory pubKeys = SSTORE2.read(pointer);
        uint256 nodesAmount = pubKeys.getNodesLength();

        if (nodesAmount == MAX_NODES) revert MaxNodesReached();
        if (nodeIndexes[node] != 0) revert NodeAlreadyAdded(node);

        // Store with 1-based indexing
        nodeIndexes[node] = nodesAmount;
        pubKeys.addNode(pubkey);

        address newPointer = SSTORE2.write(pubKeys);
        pointer = newPointer;

        emit LogNodeAdded(node, nodesAmount, newPointer);
    }

    /// @notice Remove a node from the aggregator group
    /// @param node Address of the node to remove
    function removeNode(address node) external override onlyNodeManager {
        uint256 index = nodeIndexes[node];
        if (index == 0) revert NotNode(node);

        // Note: Pending rewards remain and can still be claimed after removal

        bytes memory pubKeys = SSTORE2.read(pointer);
        bool orderChanged = pubKeys.removeNode(index);

        if (orderChanged) {
            address movedNode = pubKeys.getNode(index).toAddress();
            nodeIndexes[movedNode] = index;
        }

        address newPointer = SSTORE2.write(pubKeys);
        pointer = newPointer;
        delete nodeIndexes[node];

        emit LogNodeRemoved(node, index, newPointer);
    }

    /// @notice Check if a node is currently registered
    /// @param node Address of the node
    /// @return isActive Whether the node is active
    function isNode(
        address node
    ) external view override returns (bool isActive) {
        return nodeIndexes[node] != 0;
    }

    /// @notice Get the total number of nodes in the aggregator group
    /// @return totalNodes The total number of nodes
    function getTotalNodes()
        external
        view
        override
        returns (uint256 totalNodes)
    {
        bytes memory pubKeys = SSTORE2.read(pointer);
        totalNodes = pubKeys.getNodesLength() - START_INDEX;
    }

    /// @notice Get the hash of the nodes set
    /// @return hash The hash of the nodes set
    function getNodesSetHash() external view override returns (bytes32 hash) {
        hash = keccak256(SSTORE2.read(pointer));
    }

    /// @notice Verify a Schnorr signature
    /// @param message The message to verify
    /// @param schnorrData The Schnorr signature data
    /// @param minSignaturesThreshold The minimum number of signatures required
    function verifySignature(
        bytes32 message,
        SchnorrSignature calldata schnorrData,
        uint256 minSignaturesThreshold
    ) external view override {
        if (schnorrData.signature == bytes32(0)) revert InvalidSignature();
        if (schnorrData.signers.length == 0) revert InvalidSignersOrder();
        if (schnorrData.commitment == address(0)) revert InvalidCommitment();

        uint256 numberSigners = schnorrData.signers.length;
        if (numberSigners < minSignaturesThreshold) {
            revert NotEnoughSignatures(numberSigners, minSignaturesThreshold);
        }

        LibSecp256k1.Point[] memory pubKeys = _getPubKeys();
        uint256 signerSetLength = pubKeys.length;
        uint256 firstIndex = schnorrData.signers[0];

        if (firstIndex == 0 || firstIndex >= signerSetLength) {
            revert InvalidIndex(firstIndex);
        }

        LibSecp256k1.JacobianPoint memory aggPubKey = pubKeys[firstIndex]
            .toJacobian();

        for (uint256 i = START_INDEX; i < numberSigners; i++) {
            uint256 signerIndex = schnorrData.signers[i];

            if (signerIndex == 0 || signerIndex >= signerSetLength) {
                revert InvalidIndex(signerIndex);
            }
            if (signerIndex <= schnorrData.signers[i - 1]) {
                revert InvalidSignersOrder();
            }

            aggPubKey.addAffinePoint(pubKeys[signerIndex]);
        }

        bool isValid = aggPubKey.toAffine().verifySignature(
            message,
            schnorrData.signature,
            schnorrData.commitment
        );
        if (!isValid) revert InvalidSignature();
    }

    /// @notice Record participation for a feed using a bitmap
    /// @param feed Feed address to record participation for
    /// @param signersBitmap Bitmap representing which nodes participated (0-based positions)
    /// @return index The index in the feed's bitmap array where this participation was stored
    /// @dev Just stores the bitmap, rewards are distributed separately
    function recordParticipation(
        address feed,
        uint256 signersBitmap
    ) external onlyFeedManager returns (uint256 index) {
        if (signersBitmap == 0) revert InvalidBitmap();
        if (feed == address(0)) revert InvalidFeed();

        // Add bitmap to the feed's array
        feedParticipation[feed].push(signersBitmap);

        emit FeedParticipationRecorded(
            feed,
            signersBitmap
        );
    }

    /// @notice Distribute rewards for a node from new participations in a feed
    /// @param feed Feed address to distribute rewards for
    /// @param node Node address to distribute rewards to
    /// @dev Distributes rewards from lastDistributedIndex + 1 to latest participation
    function distributeReward(address feed, address node, uint256 toIndex) external {
        if (feed == address(0)) revert InvalidFeed();

        uint256 nodeIndex = nodeIndexes[node];
        if (nodeIndex == 0) revert NotNode(node);

        uint256[] storage participations = feedParticipation[feed];
        if (participations.length == 0) revert InvalidFeed();

        uint256 lastDistributed = nodeLastDistributedIndex[feed][node];

        // Check if there are new participations to distribute
        require(toIndex > lastDistributed || toIndex < participations.length, InvalidIndex(toIndex));

        uint256 bitmapPosition = nodeIndex - 1; // Convert 1-based index to 0-based bitmap position
        uint256 participationsCount = 0;

        // Iterate through new participations
        for (uint256 i = lastDistributed + 1; i <= toIndex; i++) {
            uint256 bitmap = participations[i];

            // Check if node participated in this bitmap
            if ((bitmap >> bitmapPosition) & 1 == 1) {
                participationsCount++;
            }
        }

        uint256 totalReward = participationsCount * pricePerResponse;

        if (totalReward > 0) {
            pendingRewards[node] += participationsCount * pricePerResponse;
        }

        // Update last distributed index
        nodeLastDistributedIndex[feed][node] = toIndex;

        emit RewardDistributed(
            feed,
            node,
            lastDistributed + 1,
            toIndex,
            totalReward
        );
    }

    /// @notice Claim pending rewards for the calling node
    /// @dev Transfers tokens to node and sets pending rewards to 0
    function claimRewards() external nonReentrant {
        _claimRewards(msg.sender);
    }

    /// @notice Claim rewards for a specific node (only by feeds manager)
    /// @param node Node address to claim rewards for
    function claimRewardsFor(
        address node
    ) external onlyFeedManager nonReentrant {
        _claimRewards(node);
    }

    /// @notice Internal function to claim rewards
    /// @param node Address of the node claiming rewards
    function _claimRewards(address node) internal {
        uint256 amount = pendingRewards[node];
        if (amount == 0) revert NoRewardsToClaim();

        pendingRewards[node] = 0;
        rewardToken.safeTransfer(node, amount);

        emit RewardsClaimed(node, amount);
    }

    /// @notice Update the price per response
    /// @param newPrice New price per response in reward tokens
    function setPricePerResponse(uint256 newPrice) external {
        if (newPrice == 0) revert InvalidPricePerResponse();

        uint256 oldPrice = pricePerResponse;
        pricePerResponse = newPrice;

        emit PricePerResponseUpdated(oldPrice, newPrice);
    }

    /// @notice Get feed participation data
    /// @param feed Feed address to get data for
    /// @return bitmaps Array of participation bitmaps for the feed
    function getFeedParticipation(
        address feed
    ) external view returns (uint256[] memory bitmaps) {
        return feedParticipation[feed];
    }

    /// @notice Get specific participation bitmap for a feed at given index
    /// @param feed Feed address
    /// @param index Index in the feed's bitmap array
    /// @return bitmap Participation bitmap at the specified index
    function getFeedParticipationAtIndex(
        address feed,
        uint256 index
    ) external view returns (uint256 bitmap) {
        uint256[] storage participations = feedParticipation[feed];
        if (index >= participations.length) revert InvalidIndex(index);
        return participations[index];
    }

    /// @notice Get the last distributed index for a node in a feed
    /// @param feed Feed address
    /// @param node Node address
    /// @return lastIndex Last distributed index (0 means no distributions yet)
    function getNodeLastDistributedIndex(
        address feed,
        address node
    ) external view returns (uint256 lastIndex) {
        return nodeLastDistributedIndex[feed][node];
    }

    /// @notice Get node information including rewards and participation
    /// @param node Address of the node
    /// @return nodeIndex Index of the node (1-based)
    /// @return pending Pending rewards
    function getNodeInfo(
        address node
    )
        external
        view
        returns (
            uint256 nodeIndex,
            uint256 pending
        )
    {
        return (
            nodeIndexes[node],
            pendingRewards[node]
        );
    }

    /// @notice Get all registered node addresses
    /// @return nodes Array of node addresses
    function getAllNodes() external view returns (address[] memory nodes) {
        bytes memory pubKeysData = SSTORE2.read(pointer);
        uint256 totalNodes = pubKeysData.getNodesLength();

        if (totalNodes <= START_INDEX) {
            return new address[](0);
        }

        nodes = new address[](totalNodes - START_INDEX);
        for (uint256 i = START_INDEX; i < totalNodes; i++) {
            nodes[i - START_INDEX] = pubKeysData.getNode(i).toAddress();
        }
    }

    /// @notice Get public key for a node
    /// @param node Address of the node
    /// @return pubkey Public key of the node
    function getNodePublicKey(
        address node
    ) external view returns (LibSecp256k1.Point memory pubkey) {
        uint256 index = nodeIndexes[node];
        if (index == 0) revert NotNode(node);

        bytes memory pubKeysData = SSTORE2.read(pointer);
        return pubKeysData.getNode(index);
    }

    /// @notice Emergency function to withdraw tokens (only protocol admin)
    /// @param token Token to withdraw
    /// @param amount Amount to withdraw
    /// @param to Recipient address
    function emergencyWithdraw(
        IERC20 token,
        uint256 amount,
        address to
    ) external {
        accessControlManager.verifyProtocolAdmin(msg.sender);
        token.safeTransfer(to, amount);
    }

    /// @notice Internal function to get public keys array
    /// @return pubKeys Array of public keys
    function _getPubKeys()
        internal
        view
        returns (LibSecp256k1.Point[] memory pubKeys)
    {
        pubKeys = abi.decode(SSTORE2.read(pointer), (LibSecp256k1.Point[]));
    }

    /// @notice Efficient popcount implementation using bit manipulation
    /// @param x Input bitmap
    /// @return count Number of set bits
    function _popcount(uint256 x) internal pure returns (uint256 count) {
        // Brian Kernighan's algorithm - efficient for sparse bitmaps
        while (x != 0) {
            x &= x - 1; // Remove the lowest set bit
            count++;
        }
    }
}
