// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;
import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

import {ERC165Checker} from "./libs/ERC165Checker.sol";
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
contract Treasury is ITreasury, ERC165, ReentrancyGuard, Initializable {
    using SafeERC20 for IERC20;
    using ERC165Checker for address;

    IERC20 internal immutable _underlying;
    IAccessControlManager internal _accessControlManager;

    modifier onlyProtocolAdmin() {
        _accessControlManager.verifyProtocolAdmin(msg.sender);
        _;
    }

    constructor(IERC20 underlying) {
        require(underlying.totalSupply() > 0, InvalidUnderlying());

        _underlying = underlying;
    }

    function initialize(address accessControlManager) external override initializer {
        accessControlManager.shouldSupport(type(IAccessControlManager).interfaceId);

        accessControlManager = accessControlManager;
    }

    /// @notice Deposit funds into the treasury
    /// @param from Address to deposit from
    /// @param amount Amount to deposit
    function deposit(address from, uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (from == address(0)) revert ZeroAddress();

        // Transfer tokens from sender to treasury
        uint256 balanceBefore = _underlying.balanceOf(address(this));
        _underlying.safeTransferFrom(from, address(this), amount);
        uint256 actualAmount = _underlying.balanceOf(address(this)) - balanceBefore;


        emit FundsDeposited(address(_underlying), from, actualAmount);
    }

    function payReward(address recipient, uint256 amount) external {
    //     if (amount == 0) revert ZeroAmount();
    //     if (recipient == address(0)) revert ZeroAddress();

    //     uint256 balanceBefore = _underlying.balanceOf(address(this));
    //     require(balanceBefore >= amount, InsufficientBalance());

    //     _underlying.safeTransfer(recipient, amount);
    //     uint256 actualAmount = _underlying.balanceOf(address(this)) - balanceBefore;

        emit RewardsPaid(recipient, amount);
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
        uint256 actualBalance = _underlying.balanceOf(address(this));
        if (actualBalance < amount) revert InsufficientBalance();

        // Transfer tokens
        token.safeTransfer(to, amount);

        emit FundsWithdrawn(address(token), to, amount);
    }

    function setAccessControlManager(address accessControlManager) external override onlyProtocolAdmin {
        accessControlManager.shouldSupport(type(IAccessControlManager).interfaceId);
        _accessControlManager = IAccessControlManager(accessControlManager);
    }

    function getUnderlying() external view override returns (address underlying) {
        underlying = address(_underlying);
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(ITreasury).interfaceId || super.supportsInterface(interfaceId);
    }
} 