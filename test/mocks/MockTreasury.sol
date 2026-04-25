// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ITreasury} from "../../src/interfaces/ITreasury.sol";

contract MockTreasury is ITreasury {
    mapping(address => uint256) public deposits;
    mapping(address => uint256) public rewards;
    address public underlying;
    
    constructor() {
        underlying = address(0x1); // Mock USDC address
    }
    
    function initialize(address accessControlManager) external {
        // Mock implementation - no actual initialization needed
    }
    
    function deposit(address from, uint256 amount) external {
        deposits[from] += amount;
        emit FundsDeposited(address(0), from, amount);
    }
    
    function payReward(address recipient, uint256 amount) external {
        rewards[recipient] += amount;
        emit RewardsPaid(recipient, amount);
    }
    
    function emergencyWithdraw(IERC20 token, uint256 amount, address to) external {
        // Mock implementation - just emit event
        emit FundsWithdrawn(address(token), to, amount);
    }
    
    function setAccessControlManager(address accessControlManager) external {
        // Mock implementation
    }
    
    function getUnderlying() external view returns (address) {
        return underlying;
    }
    
    function getDeposit(address user) external view returns (uint256) {
        return deposits[user];
    }
    
    function getReward(address user) external view returns (uint256) {
        return rewards[user];
    }
    
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(ITreasury).interfaceId || interfaceId == 0x01ffc9a7; // ERC165
    }
} 