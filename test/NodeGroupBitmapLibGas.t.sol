// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test, console2} from "forge-std/Test.sol";
import {NodeGroupBitmapLib} from "../src/libs/NodeGroupBitmapLib.sol";

/// @dev Run: `forge test --match-path test/NodeGroupBitmapLibGas.t.sol -vv`
contract NodeGroupBitmapLibGasTest is Test {
    bytes32 internal constant SEED = keccak256("MOLPHA_DERIVE_GAS_PROBE");

    function _gas(bytes32 seed, uint256 nCount, uint256 groupSize) internal returns (uint256 gasUsed, uint256 bitmap) {
        uint256 g0 = gasleft();
        bitmap = NodeGroupBitmapLib.derive(seed, nCount, groupSize);
        gasUsed = g0 - gasleft();
    }

    function _popcount(uint256 bitmap) internal pure returns (uint256 c) {
        while (bitmap != 0) {
            bitmap &= bitmap - 1;
            ++c;
        }
    }

    function test_derive_isolated_gas() public {
        uint256[] memory groupSizes = new uint256[](4);
        groupSizes[0] = 3;
        groupSizes[1] = 5;
        groupSizes[2] = 9;
        groupSizes[3] = 18;
        uint256 nCount = 32;

        for (uint256 gi; gi < groupSizes.length; ++gi) {
            uint256 groupSize = groupSizes[gi];
            (uint256 gasUsed, uint256 bm) = _gas(SEED, nCount, groupSize);
            console2.log(string.concat("nCount=", vm.toString(nCount), " groupSize=", vm.toString(groupSize)));
            console2.log(string.concat("  derive gas=", vm.toString(gasUsed), " pop=", vm.toString(_popcount(bm))));
        }
    }
}
