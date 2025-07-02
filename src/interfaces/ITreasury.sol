// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title ITreasury
/// @notice Interface for the Treasury contract that manages protocol funds
interface ITreasury {
    // Events
    event FundsDeposited(address indexed token, address indexed from, uint256 amount);
    event RewardPaid(address indexed token, address indexed to, uint256 amount);
    event FundsWithdrawn(address indexed token, address indexed to, uint256 amount);
    event PayerAuthorized(address indexed payer);
    event PayerRevoked(address indexed payer);
    event DepositSourceAuthorized(address indexed source);
    event DepositSourceRevoked(address indexed source);

    // Errors
    error UnauthorizedPayer();
    error UnauthorizedDepositSource();
    error InsufficientBalance();
    error ZeroAmount();
    error ZeroAddress();
    error TransferFailed();

    /// @notice Deposit funds into the treasury
    /// @param token Token to deposit
    /// @param amount Amount to deposit
    function deposit(IERC20 token, uint256 amount) external;

    /// @notice Pay rewards to a recipient (only authorized payers)
    /// @param token Token to pay
    /// @param recipient Recipient address
    /// @param amount Amount to pay
    function payReward(IERC20 token, address recipient, uint256 amount) external;

    /// @notice Authorize an address to pay rewards
    /// @param payer Address to authorize
    function authorizePayer(address payer) external;

    /// @notice Revoke payer authorization
    /// @param payer Address to revoke
    function revokePayer(address payer) external;

    /// @notice Authorize an address to deposit funds
    /// @param source Address to authorize
    function authorizeDepositSource(address source) external;

    /// @notice Revoke deposit source authorization
    /// @param source Address to revoke
    function revokeDepositSource(address source) external;

    /// @notice Check if an address is an authorized payer
    /// @param payer Address to check
    /// @return Whether the address is authorized
    function isAuthorizedPayer(address payer) external view returns (bool);

    /// @notice Check if an address is an authorized deposit source
    /// @param source Address to check
    /// @return Whether the address is authorized
    function isAuthorizedDepositSource(address source) external view returns (bool);

    /// @notice Get the balance of a specific token
    /// @param token Token to check
    /// @return Balance of the token
    function getBalance(IERC20 token) external view returns (uint256);

    /// @notice Emergency withdrawal (only protocol admin)
    /// @param token Token to withdraw
    /// @param amount Amount to withdraw
    /// @param to Recipient address
    function emergencyWithdraw(IERC20 token, uint256 amount, address to) external;
} 