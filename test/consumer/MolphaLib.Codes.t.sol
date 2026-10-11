// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";

import {MolphaLib} from "../../src/consumer/MolphaLib.sol";
import {VerifyCodes} from "../../src/libs/VerifyCodes.sol";

/// @notice The one place `MolphaLib` and `VerifyCodes` meet.
/// @dev `isValid` returns either space through a single `uint8`, so the two tables must never
///      overlap. `MolphaLib` deliberately does not import `VerifyCodes`, so nothing but this
///      suite enforces the split.
contract MolphaLibCodesTest is Test {
    uint8 internal constant LIBRARY_FLOOR = 0xF0;

    function test_libraryCodesAreAllAtOrAboveTheFloor() public pure {
        assertGe(MolphaLib.L_WRONG_SOURCE, LIBRARY_FLOOR);
        assertGe(MolphaLib.L_THRESHOLD_POLICY, LIBRARY_FLOOR);
        assertGe(MolphaLib.L_PAYLOAD_MISMATCH, LIBRARY_FLOOR);
        assertGe(MolphaLib.L_INVALID_POLICY, LIBRARY_FLOOR);
    }

    /// @dev Enumerated one by one rather than looped, so appending a new `R_*` without revisiting
    ///      the split fails right here.
    function test_verifierCodesAreAllBelowTheFloor() public pure {
        assertLt(VerifyCodes.R_OK, LIBRARY_FLOOR);
        assertLt(VerifyCodes.R_FEED_WITNESS, LIBRARY_FLOOR);
        assertLt(VerifyCodes.R_BAD_REGISTRY_VERSION, LIBRARY_FLOOR);
        assertLt(VerifyCodes.R_MALFORMED, LIBRARY_FLOOR);
        assertLt(VerifyCodes.R_NOT_YET_ACTIVE, LIBRARY_FLOOR);
        assertLt(VerifyCodes.R_VERSION_EXPIRED, LIBRARY_FLOOR);
        assertLt(VerifyCodes.R_COMPROMISED_QUORUM, LIBRARY_FLOOR);
        assertLt(VerifyCodes.R_BAD_QUORUM, LIBRARY_FLOOR);
        assertLt(VerifyCodes.R_BAD_AGGREGATE, LIBRARY_FLOOR);
        assertLt(VerifyCodes.R_BAD_SIGNATURE, LIBRARY_FLOOR);
        assertLt(VerifyCodes.R_STALE, LIBRARY_FLOOR);
    }

    function test_libraryCodesAreDistinct() public pure {
        uint8[4] memory codes = [
            MolphaLib.L_WRONG_SOURCE,
            MolphaLib.L_THRESHOLD_POLICY,
            MolphaLib.L_PAYLOAD_MISMATCH,
            MolphaLib.L_INVALID_POLICY
        ];
        for (uint256 i; i < codes.length; ++i) {
            for (uint256 j = i + 1; j < codes.length; ++j) {
                assertTrue(codes[i] != codes[j], "duplicate library code");
            }
        }
    }

    /// @dev Renumber alarm. These values are part of the published ABI contract.
    function test_libraryCodeValuesAreFrozen() public pure {
        assertEq(MolphaLib.L_WRONG_SOURCE, 0xF0);
        assertEq(MolphaLib.L_THRESHOLD_POLICY, 0xF1);
        assertEq(MolphaLib.L_PAYLOAD_MISMATCH, 0xF2);
        assertEq(MolphaLib.L_INVALID_POLICY, 0xF3);
    }

    /// @dev `isValid` returns `0` for success, which must remain indistinguishable from `R_OK`.
    function test_successCodeAgreesWithVerifierOk() public pure {
        assertEq(VerifyCodes.R_OK, 0);
    }
}
