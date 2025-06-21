// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockedUSDC
 * @dev A mock USDC token for testing purposes
 * @notice This contract mimics the behavior of USDC with 6 decimal places
 */
contract MockedUSDC is ERC20 {
    uint8 private constant DECIMALS = 6;
    
    constructor() ERC20("USD Coin (Mock)", "USDC") {
        // Mint initial supply to deployer (1M USDC)
        _mint(msg.sender, 1_000_000 * 10**DECIMALS);
    }

    /**
     * @dev Returns the number of decimals used to get its user representation
     * @return The number of decimals (6, same as real USDC)
     */
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }

    /**
     * @dev Mint tokens to a specific address
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint (in base units)
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @dev Mint tokens with amount in USDC units (handles decimal conversion)
     * @param to The address to mint tokens to
     * @param usdcAmount The amount in USDC (e.g., 100 for 100 USDC)
     */
    function mintUSDC(address to, uint256 usdcAmount) external {
        _mint(to, usdcAmount * 10**DECIMALS);
    }

    /**
     * @dev Burn tokens from a specific address
     * @param from The address to burn tokens from
     * @param amount The amount of tokens to burn (in base units)
     */
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    /**
     * @dev Burn tokens with amount in USDC units (handles decimal conversion)
     * @param from The address to burn tokens from
     * @param usdcAmount The amount in USDC (e.g., 100 for 100 USDC)
     */
    function burnUSDC(address from, uint256 usdcAmount) external {
        _burn(from, usdcAmount * 10**DECIMALS);
    }
}
