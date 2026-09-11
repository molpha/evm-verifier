// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";

import {VerifierLib} from "../../src/libs/VerifierLib.sol";

/// @dev Every registry version lives in one packed word, so a shift or mask that overlaps a
///      neighbouring field silently corrupts state that `verify` later trusts. These tests pin
///      the layout documented in `VerifierLib` and the independence of each field.
contract VerifierLibPackingTest is Test {
    using VerifierLib for uint256;

    uint256 internal constant MAX_COUNT = 256; // MAX_NODES; the 9-bit fields hold up to 511
    uint256 internal constant MAX_TIMESTAMP = (uint256(1) << 40) - 1;

    /// @dev Bits the layout marks reserved: 178..195 and 237..255.
    uint256 internal constant RESERVED_MASK = (((uint256(1) << 18) - 1) << 178) | (((uint256(1) << 19) - 1) << 237);

    function _assertFields(
        uint256 entry,
        address pointer,
        uint256 nodeCount,
        uint256 buffer,
        uint256 activatesAt,
        bool isLatest
    ) internal pure {
        assertEq(entry.pointerOf(), pointer, "pointer");
        assertEq(entry.nodeCount(), nodeCount, "nodeCount");
        assertEq(entry.buffer(), buffer, "buffer");
        assertEq(entry.activatesAt(), activatesAt, "activatesAt");
        assertEq(entry.isLatest(), isLatest, "isLatest");
    }

    // ---------------------------------------------------------------------
    // packEntry round-trip
    // ---------------------------------------------------------------------

    function test_packEntry_roundTripsEveryFieldAtItsMaximum() public pure {
        address pointer = address(type(uint160).max);
        uint256 entry = VerifierLib.packEntry(pointer, MAX_COUNT, MAX_COUNT, MAX_TIMESTAMP, true);

        _assertFields(entry, pointer, MAX_COUNT, MAX_COUNT, MAX_TIMESTAMP, true);
    }

    /// @dev The genesis entry: only the pointer and `isLatest` are set, and it must still read as
    ///      a live version rather than as the "does not exist" zero word.
    function test_packEntry_genesisShapeIsNonZeroAndLatest() public pure {
        address pointer = address(uint160(0xBEEF));
        uint256 entry = VerifierLib.packEntry(pointer, 0, 0, 0, true);

        assertTrue(entry != 0, "a published version is never the zero word");
        _assertFields(entry, pointer, 0, 0, 0, true);
    }

    function test_packEntry_leavesReservedBitsClear() public pure {
        uint256 entry = VerifierLib.packEntry(address(type(uint160).max), MAX_COUNT, MAX_COUNT, MAX_TIMESTAMP, true);
        assertEq(entry & RESERVED_MASK, 0, "reserved bits must stay available for future fields");
    }

    function testFuzz_packEntry_roundTripsWithinDocumentedBounds(
        address pointer,
        uint16 nodeCountSeed,
        uint16 bufferSeed,
        uint64 activatesAtSeed,
        bool isLatest
    ) public pure {
        uint256 nodeCount = uint256(nodeCountSeed) % (MAX_COUNT + 1);
        uint256 buffer = uint256(bufferSeed) % (MAX_COUNT + 1);
        uint256 activatesAt = uint256(activatesAtSeed) & MAX_TIMESTAMP;

        uint256 entry = VerifierLib.packEntry(pointer, nodeCount, buffer, activatesAt, isLatest);

        _assertFields(entry, pointer, nodeCount, buffer, activatesAt, isLatest);
        assertEq(entry & RESERVED_MASK, 0, "reserved bits");
    }

    // ---------------------------------------------------------------------
    // withIsLatest
    // ---------------------------------------------------------------------

    /// @dev The contract only ever clears this flag (on the superseded version), but the setter arm
    ///      is part of the packing contract and must not disturb neighbouring fields either.
    function test_withIsLatest_togglesBothDirectionsAndIsIdempotent() public pure {
        uint256 entry = VerifierLib.packEntry(address(uint160(0xABCD)), 4, 2, 1_700_000_000, true);

        uint256 cleared = entry.withIsLatest(false);
        assertFalse(cleared.isLatest());
        assertEq(cleared.withIsLatest(false), cleared, "clearing twice is a no-op");

        uint256 restored = cleared.withIsLatest(true);
        assertTrue(restored.isLatest());
        assertEq(restored, entry, "toggling back reproduces the original word");
        assertEq(restored.withIsLatest(true), restored, "setting twice is a no-op");
    }

    function testFuzz_withIsLatest_touchesOnlyTheFlagBit(
        address pointer,
        uint16 nodeCountSeed,
        uint16 bufferSeed,
        uint64 activatesAtSeed,
        bool startLatest,
        bool target
    ) public pure {
        uint256 nodeCount = uint256(nodeCountSeed) % (MAX_COUNT + 1);
        uint256 buffer = uint256(bufferSeed) % (MAX_COUNT + 1);
        uint256 activatesAt = uint256(activatesAtSeed) & MAX_TIMESTAMP;

        uint256 entry = VerifierLib.packEntry(pointer, nodeCount, buffer, activatesAt, startLatest);
        uint256 updated = entry.withIsLatest(target);

        _assertFields(updated, pointer, nodeCount, buffer, activatesAt, target);

        uint256 flagBit = uint256(1) << 236;
        assertEq(updated & ~flagBit, entry & ~flagBit, "every bit outside the flag is preserved");
    }
}
