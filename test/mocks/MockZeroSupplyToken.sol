// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockZeroSupplyToken is ERC20 {
    constructor() ERC20("ZeroSupply", "ZERO") {
        // Don't mint any tokens, so totalSupply remains 0
    }
}