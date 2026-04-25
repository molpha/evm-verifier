// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.31;

// import {AccessControl}    from "openzeppelin-contracts/contracts/access/AccessControl.sol";
// import {ReentrancyGuard}  from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
// import {IERC20}           from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
// import {SafeERC20}        from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
// import {MerkleProof}      from "openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";

// /**
//  * @title RewardPoolUSDC (Equal-Share Epoch Pool)
//  * @notice Per-epoch USDC pots split equally among nodes that met activity threshold.
//  *         Nodes "mint" one share per epoch by proving inclusion in the Merkle active set.
//  *         After a cooldown, shares are redeemed pro-rata from the epoch pot.
//  *
//  * Design goals:
//  * - No per-job / per-epoch bitmaps on-chain.
//  * - O(1) storage per claimer per-epoch (just a minted flag + share unit).
//  * - “First-valid-wins” sealing can be enabled later; default is role-gated.
//  *
//  * Leaf format (binds node address to its index to avoid replay):
//  *   leaf = keccak256(abi.encodePacked(uint8(1), uint32(nodeIndex), address(node)))
//  */
// contract RewardPoolUSDC is AccessControl, ReentrancyGuard {
//     using SafeERC20 for IERC20;

//     // ───────────────────────── Roles
//     bytes32 public constant AGGREGATOR_ROLE = keccak256("AGGREGATOR_ROLE"); // may seal epochs
//     bytes32 public constant TREASURY_ROLE   = keccak256("TREASURY_ROLE");   // may fund epochs

//     // ───────────────────────── Types
//     struct Epoch {
//         bytes32 activeRoot;     // Merkle root of active nodes for this epoch
//         uint256 usdcPot;        // Pot available for redemption
//         uint64  sealTime;       // block.timestamp when sealed
//         bool    sealed;         // true once sealed
//         uint256 totalShares;    // total shares minted for this epoch
//     }

//     // ───────────────────────── Immutables / Config
//     IERC20  public immutable USDC;
//     uint64  public immutable COOLDOWN;       // seconds after seal before redeem allowed
//     uint64  public          lastSealed;      // latest sealed epoch id (monotonic)

//     // ───────────────────────── Storage
//     mapping(uint64 => Epoch) public epochs;
//     // minted[epoch][node] → whether node already minted its single equal share
//     mapping(uint64 => mapping(address => bool)) public minted;
//     // shares[epoch][node] → stored to allow partial burns or future weighting (kept == SHARE_UNIT now)
//     mapping(uint64 => mapping(address => uint256)) public shares;

//     // Equal-share unit (fixed). Using 1e6 keeps math stable if you later weight shares.
//     uint256 internal constant SHARE_UNIT = 1e6;

//     // ───────────────────────── Events
//     event EpochSealed(uint64 indexed epoch, bytes32 activeRoot, uint64 sealTime);
//     event EpochFunded(uint64 indexed epoch, uint256 amount, address indexed from);
//     event SharesMinted(uint64 indexed epoch, address indexed node, uint256 shares);
//     event Redeemed(uint64 indexed epoch, address indexed node, uint256 shares, uint256 usdcOut);

//     constructor(address usdc, uint64 cooldownSeconds, address admin) {
//         require(usdc != address(0), "USDC=0");
//         USDC     = IERC20(usdc);
//         COOLDOWN = cooldownSeconds;

//         _grantRole(DEFAULT_ADMIN_ROLE, admin);
//         _grantRole(AGGREGATOR_ROLE, admin);
//         _grantRole(TREASURY_ROLE, admin);
//     }

//     // ───────────────────────── Admin / Treasury

//     /**
//      * @notice Seal a new epoch with the active set Merkle root.
//      * @dev Requires strictly monotonic epoch ids.
//      * @dev To switch to "first-valid-wins", remove the role check and guard on !epochs[e].sealed.
//      */
//     function sealEpoch(uint64 epoch, bytes32 activeRoot) external onlyRole(AGGREGATOR_ROLE) {
//         require(activeRoot != bytes32(0), "root=0");
//         // strictly increasing
//         require(epoch == lastSealed + 1, "bad epoch");
//         Epoch storage E = epochs[epoch];
//         require(!E.sealed, "sealed");

//         E.activeRoot = activeRoot;
//         E.sealTime   = uint64(block.timestamp);
//         E.sealed     = true;

//         lastSealed = epoch;
//         emit EpochSealed(epoch, activeRoot, E.sealTime);
//     }

//     /**
//      * @notice Fund an epoch’s USDC pot. Can be called pre- or post-seal.
//      * @dev Multiple fundings accumulate.=-[]';/;p0[=]{"_p;0/"}
//      */
//     function fundEpoch(uint64 epoch, uint256 amount) external onlyRole(TREASURY_ROLE) {
//         require(amount > 0, "amount=0");
//         USDC.safeTransferFrom(msg.sender, address(this), amount);
//         epochs[epoch].usdcPot += amount;
//         emit EpochFunded(epoch, amount, msg.sender);
//     }

//     // ───────────────────────── Node side

//     /**
//      * @notice Mint equal-share for an epoch by proving you’re in the active set.
//      * @param epoch Epoch id to mint for (must be sealed, can mint during cooldown).
//      * @param nodeIndex 1-based index of the node in the off-chain active list
//      * @param merkleProof Merkle proof of inclusion for leaf = keccak(1, nodeIndex, msg.sender)
//      */
//     function mintEpochShare(
//         uint64 epoch,
//         uint32 nodeIndex,
//         bytes32[] calldata merkleProof
//     ) external {
//         Epoch storage E = epochs[epoch];
//         require(E.sealed, "unsealed");

//         // prevent double minting
//         require(!minted[epoch][msg.sender], "already minted");

//         // Rebuild leaf and verify
//         bytes32 leaf = keccak256(abi.encodePacked(uint8(1), nodeIndex, msg.sender));
//         require(MerkleProof.verify(merkleProof, E.activeRoot, leaf), "bad proof");

//         minted[epoch][msg.sender] = true;
//         shares[epoch][msg.sender] = SHARE_UNIT;
//         E.totalShares            += SHARE_UNIT;

//         emit SharesMinted(epoch, msg.sender, SHARE_UNIT);
//     }

//     /**
//      * @notice Redeem your equal-share for an epoch after cooldown; pays USDC pro-rata.
//      * @dev Order-independent: we burn shares and decrement pot proportionally.
//      */
//     function redeem(uint64 epoch) external nonReentrant {
//         Epoch storage E = epochs[epoch];
//         require(E.sealed, "unsealed");
//         require(block.timestamp >= E.sealTime + COOLDOWN, "cooldown");

//         uint256 s = shares[epoch][msg.sender];
//         require(s != 0, "no shares");

//         uint256 ts = E.totalShares;
//         require(ts != 0, "ts=0");

//         // Pro-rata payout, order-independent
//         uint256 payout = (E.usdcPot * s) / ts;

//         // Burn user shares and decrease totals
//         shares[epoch][msg.sender] = 0;
//         E.totalShares            -= s;
//         E.usdcPot                -= payout;

//         USDC.safeTransfer(msg.sender, payout);
//         emit Redeemed(epoch, msg.sender, s, payout);
//     }

//     /**
//      * @notice Batch redeem across multiple epochs (gas saver).
//      */
//     function batchRedeem(uint64[] calldata epochs_) external nonReentrant {
//         uint256 totalOut;
//         for (uint256 i = 0; i < epochs_.length; i++) {
//             uint64 e = epochs_[i];
//             Epoch storage E = epochs[e];
//             if (!E.sealed || block.timestamp < E.sealTime + COOLDOWN) continue;

//             uint256 s = shares[e][msg.sender];
//             if (s == 0) continue;

//             uint256 ts = E.totalShares;
//             if (ts == 0) continue;

//             uint256 payout = (E.usdcPot * s) / ts;

//             shares[e][msg.sender] = 0;
//             E.totalShares         -= s;
//             E.usdcPot             -= payout;
//             totalOut              += payout;

//             emit Redeemed(e, msg.sender, s, payout);
//         }
//         if (totalOut > 0) USDC.safeTransfer(msg.sender, totalOut);
//     }

//     // ───────────────────────── Views / helpers

//     function epochInfo(uint64 epoch)
//         external
//         view
//         returns (bytes32 activeRoot, uint256 usdcPot, uint64 sealTime, bool sealed, uint256 totalShares)
//     {
//         Epoch storage E = epochs[epoch];
//         return (E.activeRoot, E.usdcPot, E.sealTime, E.sealed, E.totalShares);
//     }

//     function canRedeem(uint64 epoch, address node) external view returns (bool) {
//         Epoch storage E = epochs[epoch];
//         if (!E.sealed) return false;
//         if (block.timestamp < E.sealTime + COOLDOWN) return false;
//         return shares[epoch][node] > 0;
//     }
// }