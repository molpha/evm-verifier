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
 */
contract Treasury is ITreasury, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Access control manager for role verification
    IAccessControlManager public immutable accessControlManager;
    IERC20 public immutable underlying;

    constructor(IAccessControlManager _accessControlManager) {
        accessControlManager = _accessControlManager;
    }

    modifier onlyProtocolAdmin() {
        accessControlManager.verifyProtocolAdmin(msg.sender);
        _;
    }

    /// @notice Deposit funds into the treasury
    /// @param from Address to deposit from
    /// @param amount Amount to deposit
    function deposit(address from, uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (from == address(0)) revert ZeroAddress();

        // Transfer tokens from sender to treasury
        uint256 balanceBefore = underlying.balanceOf(address(this));
        underlying.safeTransferFrom(from, address(this), amount);
        uint256 actualAmount = underlying.balanceOf(address(this)) - balanceBefore;


        emit FundsDeposited(address(underlying), from, actualAmount);
    }

    function payReward(address recipient, uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();

        uint256 balanceBefore = underlying.balanceOf(address(this));
        require(balanceBefore >= amount, InsufficientBalance());

        underlying.safeTransfer(recipient, amount);
        uint256 actualAmount = underlying.balanceOf(address(this)) - balanceBefore;

        emit RewardsPaid(recipient, actualAmount);
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

        // Transfer tokens
        token.safeTransfer(to, amount);

        emit FundsWithdrawn(address(token), to, amount);
    }
} 