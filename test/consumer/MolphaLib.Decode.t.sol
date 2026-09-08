// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";

import {MolphaLib} from "../../src/consumer/MolphaLib.sol";
import {MolphaLibHarness} from "./MolphaLibHarness.sol";

/// @notice The strict kind A decoders, at their boundaries.
contract MolphaLibDecodeTest is Test {
    MolphaLibHarness internal harness;

    function setUp() public {
        harness = new MolphaLibHarness();
    }

    // ---------------- asUint256 ----------------

    function test_asUint256Boundaries() public view {
        assertEq(harness.asUint256(bytes32(0)), 0);
        assertEq(harness.asUint256(bytes32(uint256(1))), 1);
        assertEq(harness.asUint256(bytes32(type(uint256).max)), type(uint256).max);
    }

    /// @dev A `uint32` schema is ABI-encoded left-padded into a full word; reading it as uint256
    ///      is the correct interpretation.
    function testFuzz_asUint256RoundTripsANarrowUint(uint32 x) public view {
        assertEq(harness.asUint256(bytes32(abi.encode(x))), x);
    }

    // ---------------- asInt256 ----------------

    function test_asInt256Boundaries() public view {
        assertEq(harness.asInt256(bytes32(0)), int256(0));
        assertEq(harness.asInt256(bytes32(type(uint256).max)), int256(-1));
        assertEq(harness.asInt256(bytes32(uint256(1) << 255)), type(int256).min);
        assertEq(harness.asInt256(bytes32(uint256(1) << 255) ^ bytes32(type(uint256).max)), type(int256).max);
    }

    /// @dev An `intN` schema is ABI sign-extended to a full word, so the same-width
    ///      reinterpretation preserves the value.
    function testFuzz_asInt256SignExtendsANarrowInt(int32 x) public view {
        assertEq(harness.asInt256(bytes32(abi.encode(x))), int256(x));
    }

    function testFuzz_asInt256IsATotalReinterpretation(bytes32 v) public view {
        assertEq(uint256(harness.asInt256(v) >= 0 ? 1 : 0), uint256(v) >> 255 == 0 ? 1 : 0);
    }

    // ---------------- asBool ----------------

    function test_asBoolAcceptsCanonicalEncodings() public view {
        assertFalse(harness.asBool(bytes32(0)));
        assertTrue(harness.asBool(bytes32(uint256(1))));
    }

    function test_asBoolRejectsTwo() public {
        vm.expectRevert(abi.encodeWithSelector(MolphaLib.MalformedWord.selector, bytes32(uint256(2))));
        harness.asBool(bytes32(uint256(2)));
    }

    function test_asBoolRejectsMax() public {
        vm.expectRevert(abi.encodeWithSelector(MolphaLib.MalformedWord.selector, bytes32(type(uint256).max)));
        harness.asBool(bytes32(type(uint256).max));
    }

    function testFuzz_asBoolRejectsEveryNonCanonicalWord(bytes32 v) public {
        vm.assume(uint256(v) > 1);
        vm.expectRevert(abi.encodeWithSelector(MolphaLib.MalformedWord.selector, v));
        harness.asBool(v);
    }

    // ---------------- asAddress ----------------

    function test_asAddressAcceptsCleanWords() public view {
        assertEq(harness.asAddress(bytes32(0)), address(0));
        assertEq(harness.asAddress(bytes32(uint256(type(uint160).max))), address(type(uint160).max));
    }

    function testFuzz_asAddressRoundTrips(address a) public view {
        assertEq(harness.asAddress(bytes32(abi.encode(a))), a);
    }

    function test_asAddressRejectsTheFirstDirtyBit() public {
        bytes32 dirty = bytes32(uint256(1) << 160);
        vm.expectRevert(abi.encodeWithSelector(MolphaLib.MalformedWord.selector, dirty));
        harness.asAddress(dirty);
    }

    function test_asAddressRejectsMax() public {
        vm.expectRevert(abi.encodeWithSelector(MolphaLib.MalformedWord.selector, bytes32(type(uint256).max)));
        harness.asAddress(bytes32(type(uint256).max));
    }

    function testFuzz_asAddressRejectsEveryDirtyUpperWord(bytes32 v) public {
        vm.assume(uint256(v) >> 160 != 0);
        vm.expectRevert(abi.encodeWithSelector(MolphaLib.MalformedWord.selector, v));
        harness.asAddress(v);
    }
}
