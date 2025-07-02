// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {ITreasury} from "./interfaces/ITreasury.sol";
import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";

/**
 * @title Treasury
 * @notice Central treasury for managing protocol funds and reward payouts
 * @dev Holds subscription funds and pays out rewards to nodes
 * 
 * The Treasury acts as the central fund manager for the protocol:
 * 1. Receives funds from SubscriptionRegistry when users pay for subscriptions
 * 2. Pays out rewards to nodes when they claim through RewardTracker
 * 3. Maintains authorization lists for depositors and payers
 * 4. Provides emergency withdrawal functionality for protocol admin
 * 
 * Authorization flow:
 * - SubscriptionRegistry must be authorized as a deposit source
 * - RewardTracker must be authorized as a payer
 * - Only protocol admin can manage authorizations
 */
contract Treasury is ITreasury, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Access control manager for role verification
    IAccessControlManager public immutable accessControlManager;

    /// @notice Mapping of authorized payers (e.g., RewardTracker)
    mapping(address => bool) public authorizedPayers;

    /// @notice Mapping of authorized deposit sources (e.g., SubscriptionRegistry)
    mapping(address => bool) public authorizedDepositSources;

    /// @notice Track balances per token for accounting
    mapping(IERC20 => uint256) public tokenBalances;

    constructor(IAccessControlManager _accessControlManager) {
        accessControlManager = _accessControlManager;
    }

    modifier onlyProtocolAdmin() {
        accessControlManager.verifyProtocolAdmin(msg.sender);
        _;
    }

    modifier onlyAuthorizedPayer() {
        if (!authorizedPayers[msg.sender]) revert UnauthorizedPayer();
        _;
    }

    modifier onlyAuthorizedDepositSource() {
        if (!authorizedDepositSources[msg.sender]) revert UnauthorizedDepositSource();
        _;
    }

    /// @notice Deposit funds into the treasury
    /// @param token Token to deposit
    /// @param amount Amount to deposit
    function deposit(IERC20 token, uint256 amount) external onlyAuthorizedDepositSource {
        if (amount == 0) revert ZeroAmount();
        if (address(token) == address(0)) revert ZeroAddress();

        // Transfer tokens from sender to treasury
        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        uint256 actualAmount = token.balanceOf(address(this)) - balanceBefore;

        // Update internal accounting
        tokenBalances[token] += actualAmount;

        emit FundsDeposited(address(token), msg.sender, actualAmount);
    }

    /// @notice Pay rewards to a recipient
    /// @param token Token to pay
    /// @param recipient Recipient address
    /// @param amount Amount to pay
    function payReward(
        IERC20 token,
        address recipient,
        uint256 amount
    ) external onlyAuthorizedPayer nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();
        if (address(token) == address(0)) revert ZeroAddress();

        // Check sufficient balance
        if (tokenBalances[token] < amount) revert InsufficientBalance();

        // Update internal accounting
        tokenBalances[token] -= amount;

        // Transfer tokens
        token.safeTransfer(recipient, amount);

        emit RewardPaid(address(token), recipient, amount);
    }

    /// @notice Authorize an address to pay rewards
    /// @param payer Address to authorize
    function authorizePayer(address payer) external onlyProtocolAdmin {
        if (payer == address(0)) revert ZeroAddress();
        authorizedPayers[payer] = true;
        emit PayerAuthorized(payer);
    }

    /// @notice Revoke payer authorization
    /// @param payer Address to revoke
    function revokePayer(address payer) external onlyProtocolAdmin {
        authorizedPayers[payer] = false;
        emit PayerRevoked(payer);
    }

    /// @notice Authorize an address to deposit funds
    /// @param source Address to authorize
    function authorizeDepositSource(address source) external onlyProtocolAdmin {
        if (source == address(0)) revert ZeroAddress();
        authorizedDepositSources[source] = true;
        emit DepositSourceAuthorized(source);
    }

    /// @notice Revoke deposit source authorization
    /// @param source Address to revoke
    function revokeDepositSource(address source) external onlyProtocolAdmin {
        authorizedDepositSources[source] = false;
        emit DepositSourceRevoked(source);
    }

    /// @notice Check if an address is an authorized payer
    /// @param payer Address to check
    /// @return Whether the address is authorized
    function isAuthorizedPayer(address payer) external view returns (bool) {
        return authorizedPayers[payer];
    }

    /// @notice Check if an address is an authorized deposit source
    /// @param source Address to check
    /// @return Whether the address is authorized
    function isAuthorizedDepositSource(address source) external view returns (bool) {
        return authorizedDepositSources[source];
    }

    /// @notice Get the balance of a specific token
    /// @param token Token to check
    /// @return Balance of the token
    function getBalance(IERC20 token) external view returns (uint256) {
        return tokenBalances[token];
    }

    /// @notice Emergency withdrawal
    /// @param token Token to withdraw
    /// @param amount Amount to withdraw
    /// @param to Recipient address
    function emergencyWithdraw(
        IERC20 token,
        uint256 amount,
        address to
    ) external onlyProtocolAdmin {
        if (amount == 0) revert ZeroAmount();
        if (to == address(0)) revert ZeroAddress();
        if (address(token) == address(0)) revert ZeroAddress();

        // For emergency, we use actual balance instead of internal accounting
        uint256 actualBalance = token.balanceOf(address(this));
        if (actualBalance < amount) revert InsufficientBalance();

        // Update internal accounting
        if (tokenBalances[token] >= amount) {
            tokenBalances[token] -= amount;
        } else {
            // In case of accounting mismatch, reset to 0
            tokenBalances[token] = 0;
        }

        // Transfer tokens
        token.safeTransfer(to, amount);

        emit FundsWithdrawn(address(token), to, amount);
    }

    /// @notice Sync internal accounting with actual balance
    /// @param token Token to sync
    /// @dev Call this if there's a discrepancy between internal accounting and actual balance
    function syncBalance(IERC20 token) external onlyProtocolAdmin {
        uint256 actualBalance = token.balanceOf(address(this));
        tokenBalances[token] = actualBalance;
    }
} 