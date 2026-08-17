// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";

import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";

/// @dev External wrapper for the reverting entry points, so `vm.expectRevert` arms against a real
///      call frame rather than the inlined test body.
contract Secp256k1Harness {
    function compress(LibSecp256k1.Point calldata p) external pure returns (bytes memory) {
        return LibSecp256k1.compress(p);
    }

    function decompress(bytes calldata comp) external view returns (LibSecp256k1.Point memory) {
        return LibSecp256k1.decompress(comp);
    }
}

contract LibSecp256k1Test is Test {
    using LibSecp256k1 for LibSecp256k1.Point;

    Secp256k1Harness internal harness = new Secp256k1Harness();

    function _secret(uint256 slot) internal pure returns (uint256) {
        return (uint256(keccak256(abi.encodePacked("MOLPHA_SECP_TEST_KEY", slot))) % (LibSecp256k1.Q() - 1)) + 1;
    }

    function _assertPointEq(LibSecp256k1.Point memory actual, LibSecp256k1.Point memory expected, string memory tag)
        internal
        pure
    {
        assertEq(actual.x, expected.x, string.concat(tag, ": x"));
        assertEq(actual.y, expected.y, string.concat(tag, ": y"));
    }

    // ---------------------------------------------------------------------
    // Curve constants and predicates
    // ---------------------------------------------------------------------

    function test_generatorIsOnCurveAndHasEvenParity() public pure {
        LibSecp256k1.Point memory g = LibSecp256k1.G();
        assertTrue(g.isOnCurve(), "G must satisfy y^2 = x^3 + 7");
        assertEq(g.yParity(), 0, "Gy is even, which the ecrecover trick relies on");
        assertFalse(g.isZeroPoint());
    }

    function test_zeroPointIsRecognisedAndOffCurve() public pure {
        LibSecp256k1.Point memory zero = LibSecp256k1.ZERO_POINT();
        assertTrue(zero.isZeroPoint());
        assertFalse(zero.isOnCurve(), "(0,0) does not satisfy the curve equation");
    }

    /// @dev `isZeroPoint` is an OR over both coordinates, so a half-zero point is not the sentinel.
    function test_isZeroPoint_requiresBothCoordinatesZero() public pure {
        assertFalse(LibSecp256k1.Point({x: 1, y: 0}).isZeroPoint());
        assertFalse(LibSecp256k1.Point({x: 0, y: 1}).isZeroPoint());
    }

    function test_isOnCurve_rejectsAnArbitraryOffCurvePoint() public pure {
        assertFalse(LibSecp256k1.Point({x: 1, y: 1}).isOnCurve());
    }

    function test_fieldP_matchesTheSecp256k1Prime() public pure {
        assertEq(LibSecp256k1.fieldP(), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F);
    }

    function testFuzz_yParity_matchesLowBit(uint128 slotSeed) public view {
        LibSecp256k1.Point memory p = LibSecp256k1.mulAffine(LibSecp256k1.G(), _secret(slotSeed));
        assertEq(p.yParity(), p.y & 1);
    }

    // ---------------------------------------------------------------------
    // pubkeyAddressFromScalar
    // ---------------------------------------------------------------------

    /// @dev The `ecrecover` shortcut is the only reason witness checks are O(1); it has to agree
    ///      with the scalar multiplication it replaces on every input.
    function testFuzz_pubkeyAddressFromScalar_matchesScalarMultiplication(uint128 slotSeed) public view {
        uint256 sk = _secret(slotSeed);
        assertEq(LibSecp256k1.pubkeyAddressFromScalar(sk), LibSecp256k1.mulAffine(LibSecp256k1.G(), sk).toAddress());
    }

    /// @dev Out-of-domain scalars return the zero address rather than reverting, so callers can
    ///      treat it as "not a key" — `flagCompromisedKey` relies on that.
    function test_pubkeyAddressFromScalar_returnsZeroOutsideTheScalarField() public pure {
        assertEq(LibSecp256k1.pubkeyAddressFromScalar(0), address(0), "zero scalar");
        assertEq(LibSecp256k1.pubkeyAddressFromScalar(LibSecp256k1.Q()), address(0), "scalar == Q");
        assertEq(LibSecp256k1.pubkeyAddressFromScalar(type(uint256).max), address(0), "scalar above Q");
    }

    function test_pubkeyAddressFromScalar_acceptsTheLargestValidScalar() public view {
        uint256 sk = LibSecp256k1.Q() - 1;
        assertEq(LibSecp256k1.pubkeyAddressFromScalar(sk), LibSecp256k1.mulAffine(LibSecp256k1.G(), sk).toAddress());
    }

    // ---------------------------------------------------------------------
    // compress / decompress
    // ---------------------------------------------------------------------

    function test_compress_encodesParityInThePrefix() public view {
        // Walk slots until both parities are observed, so neither prefix branch is assumed.
        bool sawEven;
        bool sawOdd;
        for (uint256 slot = 1; slot <= 8 && !(sawEven && sawOdd); ++slot) {
            LibSecp256k1.Point memory p = LibSecp256k1.mulAffine(LibSecp256k1.G(), _secret(slot));
            bytes memory comp = LibSecp256k1.compress(p);

            assertEq(comp.length, 33, "compressed keys are 33 bytes");
            assertEq(uint8(comp[0]), p.y & 1 == 0 ? 0x02 : 0x03, "prefix encodes y parity");
            _assertPointEq(LibSecp256k1.decompress(comp), p, "round trip");

            if (p.y & 1 == 0) sawEven = true;
            else sawOdd = true;
        }
        assertTrue(sawEven, "expected an even-y sample");
        assertTrue(sawOdd, "expected an odd-y sample");
    }

    function testFuzz_compressDecompress_roundTrips(uint128 slotSeed) public view {
        LibSecp256k1.Point memory p = LibSecp256k1.mulAffine(LibSecp256k1.G(), _secret(slotSeed));
        _assertPointEq(LibSecp256k1.decompress(LibSecp256k1.compress(p)), p, "round trip");
    }

    function test_compress_revertsForCoordinatesOutsideTheField() public {
        uint256 p = LibSecp256k1.fieldP();

        vm.expectRevert(LibSecp256k1.CoordinatesOutOfRange.selector);
        harness.compress(LibSecp256k1.Point({x: p, y: 1}));

        vm.expectRevert(LibSecp256k1.CoordinatesOutOfRange.selector);
        harness.compress(LibSecp256k1.Point({x: 1, y: p}));
    }

    /// @dev Compression must not launder an off-curve point into a well-formed 33-byte key that
    ///      `decompress` would later resolve to a different point.
    function test_compress_revertsForAnOffCurvePoint() public {
        vm.expectRevert(LibSecp256k1.PointNotOnCurve.selector);
        harness.compress(LibSecp256k1.Point({x: 1, y: 1}));

        LibSecp256k1.Point memory g = LibSecp256k1.G();
        vm.expectRevert(LibSecp256k1.PointNotOnCurve.selector);
        harness.compress(LibSecp256k1.Point({x: g.x, y: g.y ^ 1}));
    }

    function test_decompress_revertsForMalformedInput() public {
        vm.expectRevert(LibSecp256k1.InvalidCompressedPubkeyLength.selector);
        harness.decompress(hex"02");

        vm.expectRevert(LibSecp256k1.InvalidCompressedPubkeyLength.selector);
        harness.decompress(abi.encodePacked(bytes1(0x02), bytes32(uint256(1)), bytes1(0x00)));

        vm.expectRevert(LibSecp256k1.InvalidCompressedPubkeyPrefix.selector);
        harness.decompress(abi.encodePacked(bytes1(0x04), bytes32(uint256(1))));

        vm.expectRevert(LibSecp256k1.CompressedPubkeyXOutOfRange.selector);
        harness.decompress(abi.encodePacked(bytes1(0x02), bytes32(LibSecp256k1.fieldP())));
    }

    /// @dev `_modExp` returns a square root only for quadratic residues; for everything else the
    ///      candidate squares to `-rhs`, and the check must catch it instead of returning a point
    ///      that is not on the curve. x = 5 is such a non-residue.
    function test_decompress_revertsWhenXHasNoCurvePoint() public {
        vm.expectRevert(LibSecp256k1.PointNotOnCurve.selector);
        harness.decompress(abi.encodePacked(bytes1(0x02), bytes32(uint256(5))));

        vm.expectRevert(LibSecp256k1.PointNotOnCurve.selector);
        harness.decompress(abi.encodePacked(bytes1(0x03), bytes32(uint256(5))));
    }

    /// @dev Both parity encodings of the same x resolve to the two points of that x, and they are
    ///      reflections across the x-axis.
    function test_decompress_parityPrefixSelectsTheReflection() public view {
        bytes32 x = bytes32(LibSecp256k1.G().x);
        LibSecp256k1.Point memory even = LibSecp256k1.decompress(abi.encodePacked(bytes1(0x02), x));
        LibSecp256k1.Point memory odd = LibSecp256k1.decompress(abi.encodePacked(bytes1(0x03), x));

        assertEq(even.x, odd.x, "same x-coordinate");
        assertEq(even.y & 1, 0, "0x02 selects even y");
        assertEq(odd.y & 1, 1, "0x03 selects odd y");
        assertEq(addmod(even.y, odd.y, LibSecp256k1.fieldP()), 0, "the two roots are negatives mod P");
        assertTrue(even.isOnCurve() && odd.isOnCurve());
    }

    // ---------------------------------------------------------------------
    // Point arithmetic
    // ---------------------------------------------------------------------

    function test_mulAffine_returnsTheZeroPointForDegenerateInputs() public view {
        _assertPointEq(LibSecp256k1.mulAffine(LibSecp256k1.G(), 0), LibSecp256k1.ZERO_POINT(), "scalar 0");
        _assertPointEq(LibSecp256k1.mulAffine(LibSecp256k1.ZERO_POINT(), 5), LibSecp256k1.ZERO_POINT(), "zero point");
    }

    function test_mulAffine_byOneIsTheIdentity() public view {
        _assertPointEq(LibSecp256k1.mulAffine(LibSecp256k1.G(), 1), LibSecp256k1.G(), "1 * G");
    }

    /// @dev Doubling has its own formula; it must agree with the scalar ladder.
    function test_jacobianDouble_matchesScalarMultiplicationByTwo() public view {
        LibSecp256k1.JacobianPoint memory j = LibSecp256k1.G().toJacobian();
        LibSecp256k1.jacobianDouble(j);

        _assertPointEq(LibSecp256k1.toAffine(j), LibSecp256k1.mulAffine(LibSecp256k1.G(), 2), "2 * G");
    }

    /// @dev z = 0 is the Jacobian point at infinity; doubling it must leave it untouched rather
    ///      than divide through by zero.
    function test_jacobianDouble_leavesThePointAtInfinityUnchanged() public pure {
        LibSecp256k1.JacobianPoint memory infinity = LibSecp256k1.JacobianPoint({x: 7, y: 9, z: 0});
        LibSecp256k1.jacobianDouble(infinity);

        assertEq(infinity.x, 7);
        assertEq(infinity.y, 9);
        assertEq(infinity.z, 0);
    }

    function test_toJacobian_liftsWithUnitZ() public pure {
        LibSecp256k1.JacobianPoint memory j = LibSecp256k1.G().toJacobian();
        assertEq(j.x, LibSecp256k1.G().x);
        assertEq(j.y, LibSecp256k1.G().y);
        assertEq(j.z, 1, "an affine point lifts to z = 1");
    }

    /// @dev z == 1 short-circuits the modular inversion; the coordinates must pass through as-is.
    function test_toAffineModexpXYZ_shortCircuitsForUnitZ() public view {
        LibSecp256k1.Point memory result = LibSecp256k1.toAffineModexpXYZ(123, 456, 1);
        assertEq(result.x, 123);
        assertEq(result.y, 456);
    }

    /// @dev The aggregate public key is a sum of member keys, so point addition has to be the
    ///      homomorphic image of scalar addition. `VerifierLib.aggregatePubKey` inlines this same
    ///      formula, which makes the property the backbone of aggregate verification.
    function testFuzz_pointAdditionIsHomomorphicOverScalarAddition(uint128 slotA, uint128 slotB) public view {
        uint256 a = _secret(slotA);
        uint256 b = _secret(uint256(slotB) + 1e18); // keep the two scalars distinct
        vm.assume(a != b);

        LibSecp256k1.Point memory pa = LibSecp256k1.mulAffine(LibSecp256k1.G(), a);
        LibSecp256k1.Point memory pb = LibSecp256k1.mulAffine(LibSecp256k1.G(), b);

        (uint256 x, uint256 y, uint256 z) = LibSecp256k1.addAffinePointToXYZ(pa.x, pa.y, 1, pb.x, pb.y);
        LibSecp256k1.Point memory sum = LibSecp256k1.toAffineModexpXYZ(x, y, z);

        LibSecp256k1.Point memory expected = LibSecp256k1.mulAffine(LibSecp256k1.G(), addmod(a, b, LibSecp256k1.Q()));

        _assertPointEq(sum, expected, "(a + b) * G");
        assertTrue(sum.isOnCurve(), "the sum stays on the curve");
    }

    /// @dev The struct wrapper must produce the same result as the scalar form it delegates to.
    function test_addAffinePoint_matchesTheScalarForm() public view {
        LibSecp256k1.Point memory pa = LibSecp256k1.mulAffine(LibSecp256k1.G(), _secret(1));
        LibSecp256k1.Point memory pb = LibSecp256k1.mulAffine(LibSecp256k1.G(), _secret(2));

        LibSecp256k1.JacobianPoint memory acc = pa.toJacobian();
        LibSecp256k1.addAffinePoint(acc, pb);

        (uint256 x, uint256 y, uint256 z) = LibSecp256k1.addAffinePointToXYZ(pa.x, pa.y, 1, pb.x, pb.y);

        _assertPointEq(LibSecp256k1.toAffine(acc), LibSecp256k1.toAffineModexpXYZ(x, y, z), "struct vs scalar form");
    }

    /// @dev Node identity is `keccak256(x || y)` truncated to 20 bytes; distinct keys must not
    ///      collide into one registry slot.
    function test_toAddress_distinguishesDistinctKeys() public view {
        address a = LibSecp256k1.mulAffine(LibSecp256k1.G(), _secret(1)).toAddress();
        address b = LibSecp256k1.mulAffine(LibSecp256k1.G(), _secret(2)).toAddress();

        assertTrue(a != b);
        assertTrue(a != address(0));
    }
}
