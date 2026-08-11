// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";

import {CompromiseLib} from "../../src/libs/CompromiseLib.sol";

contract CompromiseLibTest is Test {
    function _popcount(uint256 bitmap) internal pure returns (uint256 c) {
        while (bitmap != 0) {
            bitmap &= bitmap - 1;
            ++c;
        }
    }

    /// @dev Independent swap-and-pop model over a flag array, used as the oracle for
    ///      `permuteOnRemove`: mirrors what `PubkeyBlobLib.removePubkey` does to the key blob.
    function _referencePermute(uint256 bitmap, uint256 removedIndex, uint256 nodeCount)
        internal
        pure
        returns (uint256 expected)
    {
        bool[] memory flags = new bool[](nodeCount);
        for (uint256 i; i < nodeCount; ++i) {
            flags[i] = bitmap & (uint256(1) << i) != 0;
        }

        uint256 last = nodeCount - 1;
        if (removedIndex != last) {
            flags[removedIndex] = flags[last];
        }

        for (uint256 i; i < last; ++i) {
            if (flags[i]) expected |= uint256(1) << i;
        }
    }

    // ---------------------------------------------------------------------
    // setBit / clearBit
    // ---------------------------------------------------------------------

    function test_setBit_andClearBit_areInverseOnASingleIndex() public pure {
        uint256 bitmap = CompromiseLib.setBit(0, 5);
        assertEq(bitmap, uint256(1) << 5);
        assertEq(CompromiseLib.clearBit(bitmap, 5), 0);
    }

    function test_setBit_andClearBit_areIdempotent() public pure {
        uint256 set = CompromiseLib.setBit(0, 3);
        assertEq(CompromiseLib.setBit(set, 3), set, "setting a set bit is a no-op");
        assertEq(CompromiseLib.clearBit(0, 3), 0, "clearing a clear bit is a no-op");
    }

    function test_setBit_andClearBit_reachTheTopIndex() public pure {
        uint256 top = CompromiseLib.setBit(0, 255);
        assertEq(top, uint256(1) << 255, "bit 255 is the last valid blob index");
        assertEq(CompromiseLib.clearBit(top, 255), 0);
    }

    function testFuzz_setBit_andClearBit_touchExactlyOneBit(uint256 bitmap, uint8 index) public pure {
        uint256 mask = uint256(1) << index;

        uint256 set = CompromiseLib.setBit(bitmap, index);
        assertEq(set & mask, mask, "target bit set");
        assertEq(set & ~mask, bitmap & ~mask, "other bits untouched");

        uint256 cleared = CompromiseLib.clearBit(bitmap, index);
        assertEq(cleared & mask, 0, "target bit cleared");
        assertEq(cleared & ~mask, bitmap & ~mask, "other bits untouched");
    }

    // ---------------------------------------------------------------------
    // permuteOnRemove
    // ---------------------------------------------------------------------

    /// @dev Guard for the empty set. Reached in practice when a flagged node is removed twice:
    ///      the second call runs against a registry version that has no nodes left.
    function test_permuteOnRemove_returnsEmptyForZeroNodeCount() public pure {
        assertEq(CompromiseLib.permuteOnRemove(type(uint256).max, 0, 0), 0);
        assertEq(CompromiseLib.permuteOnRemove(0, 7, 0), 0);
    }

    function test_permuteOnRemove_clearsTheFlagOfTheRemovedTail() public pure {
        uint256 bitmap = (uint256(1) << 1) | (uint256(1) << 3);
        assertEq(CompromiseLib.permuteOnRemove(bitmap, 3, 4), uint256(1) << 1, "tail flag dropped in place");
    }

    /// @dev A clean node removed from the middle inherits nothing when the tail is clean either.
    function test_permuteOnRemove_leavesUnrelatedFlagsInPlace() public pure {
        uint256 bitmap = uint256(1) << 0;
        assertEq(CompromiseLib.permuteOnRemove(bitmap, 2, 4), bitmap);
    }

    /// @dev Removing a flagged node whose tail is also flagged must keep exactly one flag: the
    ///      tail's, now sitting at the hole. Losing it would silently un-discount a leaked key.
    function test_permuteOnRemove_flaggedHoleAndFlaggedTailKeepOneFlag() public pure {
        uint256 bitmap = (uint256(1) << 1) | (uint256(1) << 3);
        uint256 permuted = CompromiseLib.permuteOnRemove(bitmap, 1, 4);

        assertEq(permuted, uint256(1) << 1);
        assertEq(_popcount(permuted), 1, "one flagged node survives");
    }

    function test_permuteOnRemove_singleNodeSetCollapsesToEmpty() public pure {
        assertEq(CompromiseLib.permuteOnRemove(1, 0, 1), 0);
        assertEq(CompromiseLib.permuteOnRemove(0, 0, 1), 0);
    }

    /// @dev Boundary: blob index 255 is the highest a 256-node registry can hold, so the swap
    ///      must work at the top of the word.
    function test_permuteOnRemove_movesFlagFromIndex255IntoTheHole() public pure {
        uint256 bitmap = uint256(1) << 255;
        assertEq(CompromiseLib.permuteOnRemove(bitmap, 0, 256), 1);
    }

    function testFuzz_permuteOnRemove_matchesSwapAndPopModel(uint256 bitmapSeed, uint8 indexSeed, uint16 countSeed)
        public
        pure
    {
        uint256 nodeCount = (uint256(countSeed) % 256) + 1;
        uint256 removedIndex = uint256(indexSeed) % nodeCount;
        uint256 mask = nodeCount == 256 ? type(uint256).max : (uint256(1) << nodeCount) - 1;
        uint256 bitmap = bitmapSeed & mask;

        uint256 permuted = CompromiseLib.permuteOnRemove(bitmap, removedIndex, nodeCount);

        assertEq(permuted, _referencePermute(bitmap, removedIndex, nodeCount), "swap-and-pop model");
        assertEq(permuted >> (nodeCount - 1), 0, "no flag survives past the shrunken node count");

        // Removing a node drops at most its own flag; nothing else may disappear or appear.
        uint256 before = _popcount(bitmap);
        uint256 removedWasFlagged = bitmap & (uint256(1) << removedIndex) != 0 ? 1 : 0;
        assertEq(_popcount(permuted), before - removedWasFlagged, "flag count accounting");
    }

    // ---------------------------------------------------------------------
    // effectiveSignerCount
    // ---------------------------------------------------------------------

    /// @dev Compromised signers are discounted from the threshold count, not removed from the
    ///      aggregate key, so this counts only the set bits a clean signer contributed.
    function test_effectiveSignerCount_discountsOverlappingFlagsOnly() public pure {
        uint256 signers = 0x0F; // indices 0..3
        assertEq(CompromiseLib.effectiveSignerCount(signers, 0), 4, "clean version discounts nothing");
        assertEq(CompromiseLib.effectiveSignerCount(signers, 0x05), 2, "indices 0 and 2 discounted");
        assertEq(CompromiseLib.effectiveSignerCount(signers, 0xF0), 4, "flags outside the signer set are inert");
        assertEq(CompromiseLib.effectiveSignerCount(signers, type(uint256).max), 0, "every signer flagged");
    }

    function test_effectiveSignerCount_isZeroForAnEmptySignerSet() public pure {
        assertEq(CompromiseLib.effectiveSignerCount(0, 0), 0);
        assertEq(CompromiseLib.effectiveSignerCount(0, type(uint256).max), 0);
    }

    function testFuzz_effectiveSignerCount_neverExceedsSignerCount(uint256 signers, uint256 compromised) public pure {
        uint256 effective = CompromiseLib.effectiveSignerCount(signers, compromised);

        assertEq(effective, _popcount(signers & ~compromised), "matches independent popcount");
        assertLe(effective, _popcount(signers), "discounting can only shrink the count");
        assertEq(effective + _popcount(signers & compromised), _popcount(signers), "clean + flagged partitions signers");
    }
}
