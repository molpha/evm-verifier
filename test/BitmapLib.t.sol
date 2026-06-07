// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";
import {BitmapLib} from "../src/libs/BitmapLib.sol";

contract BitmapLibTest is Test {
    using BitmapLib for uint256;

    function test_ctzPow2_powers_of_two() public pure {
        for (uint256 k; k < 256; ++k) {
            uint256 bit = uint256(1) << k;
            assertEq(bit.ctzPow2(), k);
        }
    }
}
