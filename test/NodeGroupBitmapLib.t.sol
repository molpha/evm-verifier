// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";
import {NodeGroupBitmapLib} from "../src/libs/NodeGroupBitmapLib.sol";

contract NodeGroupBitmapLibTest is Test {
    /// @dev Reference: iterative `keccak256(abi.encodePacked(...))` (no full-set shortcut) for equivalence checks.
    function _deriveIterative(bytes32 seed, uint32 round, uint256 nCount, uint256 groupSize)
        internal
        pure
        returns (uint256 bitmap)
    {
        if (groupSize > nCount) revert("groupSize exceeds nodeCount");
        uint256 selected;
        uint256 attempt;
        while (selected < groupSize) {
            uint256 pos = uint256(keccak256(abi.encodePacked(seed, uint256(round), attempt))) % nCount;
            uint256 bit = uint256(1) << pos;
            if (bitmap & bit == 0) {
                bitmap |= bit;
                ++selected;
            }
            unchecked {
                ++attempt;
            }
        }
    }

    function testFuzz_matches_iterative(
        bytes32 seed,
        uint8 round8,
        uint8 n,
        uint8 g
    ) public pure {
        uint256 nCount = uint256(bound(n, 1, 32));
        uint256 groupSize = uint256(bound(g, 0, nCount));
        uint32 round = uint32(round8);

        assertEq(
            NodeGroupBitmapLib.derive(seed, round, nCount, groupSize),
            _deriveIterative(seed, round, nCount, groupSize)
        );
    }

    function test_group_full_set_256() public pure {
        assertEq(
            NodeGroupBitmapLib.derive(bytes32(0), 0, 256, 256),
            type(uint256).max
        );
    }

    function test_revert_group_too_large() public {
        vm.expectRevert("groupSize exceeds nodeCount");
        this.helperDeriveOversize();
    }

    function helperDeriveOversize() external pure {
        NodeGroupBitmapLib.derive(bytes32(0), 0, 3, 4);
    }
}
