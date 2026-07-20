// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";
import {NodeGroupBitmapLib} from "../../src/libs/NodeGroupBitmapLib.sol";

contract NodeGroupBitmapLibTest is Test {
    function _popcount(uint256 bitmap) internal pure returns (uint256 c) {
        while (bitmap != 0) {
            bitmap &= bitmap - 1;
            ++c;
        }
    }

    function _maskBelow(uint256 nCount) internal pure returns (uint256 mask) {
        if (nCount == 256) {
            return type(uint256).max;
        }
        return (uint256(1) << nCount) - 1;
    }

    function test_selection_domain_constant() public pure {
        assertEq(
            keccak256("MOLPHA_SELECTION_DERIVE"), 0x492848fe5e85d4ce2231d693a58f0820a4056e2822fe5dcad7c756afe044b70b
        );
    }

    function test_derive_deterministic() public pure {
        bytes32 seed = keccak256("deterministic");
        assertEq(NodeGroupBitmapLib.derive(seed, 32, 9), NodeGroupBitmapLib.derive(seed, 32, 9));
    }

    function test_derive_popcount_matches_groupSize() public pure {
        uint256[5] memory sizes = [uint256(3), 5, 9, 18, 20];
        for (uint256 i; i < sizes.length; ++i) {
            uint256 groupSize = sizes[i];
            uint256 bm = NodeGroupBitmapLib.derive(keccak256(abi.encode("pop", i)), 32, groupSize);
            assertEq(_popcount(bm), groupSize, "popcount");
            assertEq(bm & ~_maskBelow(32), 0, "high bits clear");
        }
    }

    function test_derive_full_and_zero_edges() public pure {
        assertEq(NodeGroupBitmapLib.derive(bytes32(0), 17, 0), 0);
        assertEq(NodeGroupBitmapLib.derive(bytes32(0), 17, 17), _maskBelow(17));
        assertEq(NodeGroupBitmapLib.derive(bytes32(0), 256, 256), type(uint256).max);
    }

    function test_derive_complement_branch_popcount() public pure {
        bytes32 seed = keccak256("complement");
        for (uint256 groupSize = 9; groupSize <= 15; ++groupSize) {
            assertEq(_popcount(NodeGroupBitmapLib.derive(seed, 16, groupSize)), groupSize);
        }
    }

    function testFuzz_deriveSelectsExactBoundedGroup(bytes32 seed, uint16 nodeCountSeed, uint16 groupSizeSeed)
        public
        pure
    {
        uint256 nodeCount = (uint256(nodeCountSeed) % 256) + 1;
        uint256 groupSize = uint256(groupSizeSeed) % (nodeCount + 1);
        uint256 bitmap = NodeGroupBitmapLib.derive(seed, nodeCount, groupSize);

        assertEq(_popcount(bitmap), groupSize);
        assertEq(bitmap & ~_maskBelow(nodeCount), 0);
    }

    function test_derive_marginal_fairness() public {
        uint256 nCount = 8;
        uint256 groupSize = 4;
        uint256 rounds = 5000;
        uint256[8] memory counts;
        uint256 expected = rounds * groupSize / nCount;

        for (uint256 r; r < rounds; ++r) {
            uint256 bm = NodeGroupBitmapLib.derive(keccak256(abi.encodePacked("fair", r)), nCount, groupSize);
            for (uint256 i; i < nCount; ++i) {
                if (bm & (uint256(1) << i) != 0) {
                    unchecked {
                        ++counts[i];
                    }
                }
            }
        }

        for (uint256 i; i < nCount; ++i) {
            assertApproxEqRel(counts[i], expected, 0.12e18, "marginal fairness");
        }
    }

    function test_derive_reverts_invalid_inputs() public {
        vm.expectRevert(NodeGroupBitmapLib.ZeroNodeCount.selector);
        this.externalDerive(bytes32(0), 0, 1);
        vm.expectRevert(NodeGroupBitmapLib.NodeCountExceedsMax.selector);
        this.externalDerive(bytes32(0), 257, 1);
        vm.expectRevert(NodeGroupBitmapLib.GroupSizeExceedsNodeCount.selector);
        this.externalDerive(bytes32(0), 4, 5);
    }

    function externalDerive(bytes32 seed, uint256 nCount, uint256 groupSize) external pure returns (uint256) {
        return NodeGroupBitmapLib.derive(seed, nCount, groupSize);
    }
}
