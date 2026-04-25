// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.31;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title ITreasury
/// @notice Interface for the Treasury contract that manages protocol funds
interface ITreasury {
    // Events
    event FundsDeposited(address indexed token, address indexed from, uint256 amount);
    event RewardsPaid(address indexed to, uint256 amount);
    event FundsWithdrawn(address indexed token, address indexed to, uint256 amount);

    /// @notice Initialize the treasury
    /// @param accessControlManager The access control manager
    function initialize(address accessControlManager) external;

    /// @notice Deposit underlying tokens into the treasury
    /// @param from Address to deposit from
    /// @param amount Amount to deposit
    function deposit(address from, uint256 amount) external;

    /// @notice Pay rewards to a recipient (only authorized payers)
    /// @param recipient Recipient address
    /// @param amount Amount to pay
    function payReward(address recipient, uint256 amount) external;

    /// @notice Emergency withdrawal (only protocol admin)
    /// @param token Token to withdraw
    /// @param amount Amount to withdraw
    /// @param to Recipient address
    function emergencyWithdraw(IERC20 token, uint256 amount, address to) external;

    /// @notice Set the access control manager
    /// @param accessControlManager The access control manager
    function setAccessControlManager(address accessControlManager) external;


    /// @notice Get the underlying token
    /// @return The underlying token
    function getUnderlying() external view returns (address);
} 