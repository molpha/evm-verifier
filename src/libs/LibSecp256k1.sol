// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * @title LibSecp256k1
 *
 * @notice Library for secp256k1 elliptic curve computations
 *
 * @dev This library was developed to efficiently compute aggregated public
 *      keys for Schnorr signatures based on secp256k1, i.e. it is _not_ a
 *      general purpose elliptic curve library!
 *
 *      References to the Ethereum Yellow Paper are based on the following
 *      version: "BERLIN VERSION beacfbd – 2022-10-24".
 */
library LibSecp256k1 {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.JacobianPoint;

    error CompressedPubkeyXOutOfRange();
    error CoordinatesOutOfRange();
    error InvalidCompressedPubkeyLength();
    error InvalidCompressedPubkeyPrefix();
    error InvalidZeroParity();
    error ModExpFailed();
    error ModExpResultOutOfRange();
    error PointNotOnCurve();

    uint256 private constant ADDRESS_MASK = 0x000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    // -- Secp256k1 Constants --
    //
    // Taken from https://www.secg.org/sec2-v2.pdf.
    // See section 2.4.1 "Recommended Parameters secp256k1".

    uint256 private constant _A = 0;
    uint256 private constant _B = 7;
    uint256 private constant _P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;
    // Because p % 4 == 3, sqrt(z) = z^((p+1)/4) mod p
    uint256 private constant EXPONENT = (_P + 1) >> 2;

    /// @dev Returns the order of the group.
    function Q() internal pure returns (uint256) {
        return 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
    }

    /// @dev Returns the generator G.
    ///      Note that the generator is also called base point.
    function G() internal pure returns (Point memory) {
        return Point({
            x: 0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798,
            y: 0x483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8
        });
    }

    /// @dev Returns the zero point.
    function ZERO_POINT() internal pure returns (Point memory) {
        return Point({x: 0, y: 0});
    }

    // -- (Affine) Point --

    /// @dev Point encapsulates a secp256k1 point in Affine coordinates.
    struct Point {
        uint256 x;
        uint256 y;
    }

    /// @dev Returns the Ethereum address of `self`.
    ///
    /// @dev An Ethereum address is defined as the rightmost 160 bits of the
    ///      keccak256 hash of the concatenation of the hex-encoded x and y
    ///      coordinates of the corresponding ECDSA public key.
    ///      See "Appendix F: Signing Transactions" §134 in the Yellow Paper.
    function toAddress(Point memory self) internal pure returns (address) {
        address addr;
        // Functionally equivalent Solidity code:
        // addr = address(uint160(uint(keccak256(abi.encode(self.x, self.y)))));
        assembly ("memory-safe") {
            addr := and(keccak256(self, 0x40), ADDRESS_MASK)
        }
        return addr;
    }

    /// @dev Returns Affine point `self` in Jacobian coordinates.
    function toJacobian(Point memory self) internal pure returns (JacobianPoint memory) {
        return JacobianPoint({x: self.x, y: self.y, z: 1});
    }

    /// @dev Returns whether `self` is the zero point.
    function isZeroPoint(Point memory self) internal pure returns (bool) {
        return (self.x | self.y) == 0;
    }

    /// @dev Returns whether `self` is a point on the curve.
    ///
    /// @dev The secp256k1 curve is specified as y² ≡ x³ + ax + b (mod P)
    ///      where:
    ///         a = 0
    ///         b = 7
    function isOnCurve(Point memory self) internal pure returns (bool) {
        uint256 left = mulmod(self.y, self.y, _P);
        // Note that adding a * x can be waived as ∀x: a * x = 0.
        uint256 right = addmod(mulmod(self.x, mulmod(self.x, self.x, _P), _P), _B, _P);

        return left == right;
    }

    /// @dev Returns the parity of `self`'s y coordinate.
    ///
    /// @dev The value 0 represents an even y value and 1 represents an odd y
    ///      value.
    ///      See "Appendix F: Signing Transactions" in the Yellow Paper.
    function yParity(Point memory self) internal pure returns (uint256) {
        return self.y & 1;
    }

    // -- Jacobian Point --

    /// @dev JacobianPoint encapsulates a secp256k1 point in Jacobian
    ///      coordinates.
    struct JacobianPoint {
        uint256 x;
        uint256 y;
        uint256 z;
    }

    /// @dev Returns Jacobian point `self` in Affine coordinates.
    ///
    /// @custom:invariant Reverts iff out of gas.
    /// @custom:invariant Does not run into an infinite loop.
    function toAffine(JacobianPoint memory self) internal pure returns (Point memory) {
        Point memory result;

        // Compute z⁻¹, i.e. the modular inverse of self.z.
        uint256 zInv = _invMod(self.z);

        // Compute (z⁻¹)² (mod P)
        uint256 zInv_2 = mulmod(zInv, zInv, _P);

        // Compute self.x * (z⁻¹)² (mod P), i.e. the x coordinate of given
        // Jacobian point in Affine representation.
        result.x = mulmod(self.x, zInv_2, _P);

        // Compute self.y * (z⁻¹)³ (mod P), i.e. the y coordinate of given
        // Jacobian point in Affine representation.
        result.y = mulmod(self.y, mulmod(zInv, zInv_2, _P), _P);

        return result;
    }

    /// @dev Scalar-input variant of toAffineModexp.  Accepts the Jacobian coordinates
    ///      as plain scalars so the caller can avoid allocating a JacobianPoint memory
    ///      struct and the three MLOADs that would follow.
    function toAffineModexpXYZ(uint256 jx, uint256 jy, uint256 jz) internal view returns (Point memory result) {
        // Affine accumulator (`z == 1`): skip field inversion (~modexp cost).
        if (jz == 1) {
            return Point({x: jx, y: jy});
        }
        uint256 zInv = _modExp(jz, _P - 2, _P);
        uint256 zInv2 = mulmod(zInv, zInv, _P);
        result.x = mulmod(jx, zInv2, _P);
        result.y = mulmod(jy, mulmod(zInv, zInv2, _P), _P);
    }

    /// @dev Mixed Jacobian+Affine EC addition with all inputs and outputs as plain
    ///      scalars rather than memory structs (madd-2007-bl, z₂=1).
    ///
    ///      This eliminates the 3-MLOAD / 3-MSTORE round-trip that the struct-based
    ///      addAffinePoint incurs on every loop iteration, and lets the compiler (with
    ///      via-ir) keep the accumulator entirely in Yul stack slots.
    ///
    ///      Uses sub(P, x) for negation throughout; this is safe because all intermediate
    ///      values produced by mulmod/addmod lie in [0, P-1] so P-x ≥ 1.
    ///
    ///      Reference: https://hyperelliptic.org/EFD/g1p/auto-shortw-jacobian.html#addition-madd-2007-bl
    function addAffinePointToXYZ(uint256 jx, uint256 jy, uint256 jz, uint256 px, uint256 py)
        internal
        pure
        returns (uint256 nax, uint256 nay, uint256 naz)
    {
        assembly ("memory-safe") {
            let P := 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
            let z2 := mulmod(jz, jz, P) // z₁²
            let z3 := mulmod(z2, jz, P) // z₁³
            let h := addmod(mulmod(px, z2, P), sub(P, jx), P) // u − x₁
            let h2 := mulmod(h, h, P) // h²
            let i2 := mulmod(4, h2, P) // 4h²
            let v := mulmod(jx, i2, P) // x₁·i
            let j := mulmod(h, i2, P) // h·i
            let r := mulmod(2, addmod(mulmod(py, z3, P), sub(P, jy), P), P) // 2(s−y₁)
            // z = (z₁+h)² − z₁² − h²
            let azh := addmod(jz, h, P)
            naz := addmod(mulmod(azh, azh, P), addmod(sub(P, z2), sub(P, h2), P), P)
            // x = r² − j − 2v
            nax := addmod(mulmod(r, r, P), addmod(sub(P, j), sub(P, mulmod(2, v, P)), P), P)
            // y = r·(v − x_new) − 2·y₁·j
            nay := addmod(mulmod(r, addmod(v, sub(P, nax), P), P), sub(P, mulmod(2, mulmod(jy, j, P), P)), P)
        }
    }

    /// @dev Adds Affine point `p` to Jacobian point `self`.
    ///
    ///      It is the caller's responsibility to ensure given points are on the
    ///      curve!
    ///
    ///      Computation based on: https://www.hyperelliptic.org/EFD/g1p/auto-shortw-jacobian.html#addition-madd-2007-bl.
    ///
    ///      Note that the formula assumes z2 = 1, which always holds if z2's
    ///      point is given in Affine coordinates.
    ///
    ///      Note that eventhough the function is marked as pure, to be
    ///      understood as only being dependent on the input arguments, it
    ///      nevertheless has side effects by writing the result into the
    ///      `self` memory variable.
    ///
    /// @custom:invariant Only mutates `self` memory variable.
    /// @custom:invariant Reverts iff out of gas.
    /// @custom:invariant Uses constant amount of gas.
    function addAffinePoint(JacobianPoint memory self, Point memory p) internal pure {
        // Addition formula:
        //      x = r² - j - (2 * v)             (mod P)
        //      y = (r * (v - x)) - (2 * y1 * j) (mod P)
        //      z = (z1 + h)² - z1² - h²         (mod P)
        //
        // where:
        //      r = 2 * (s - y1) (mod P)
        //      j = h * i        (mod P)
        //      v = x1 * i       (mod P)
        //      h = u - x1       (mod P)
        //      s = y2 * z1³     (mod P)       Called s2 in reference
        //      i = 4 * h²       (mod P)
        //      u = x2 * z1²     (mod P)       Called u2 in reference
        //
        // and:
        //      x1 = self.x
        //      y1 = self.y
        //      z1 = self.z
        //      x2 = p.x
        //      y2 = p.y
        //
        // Note that in order to save memory allocations the result is stored
        // in the self variable, i.e. the following holds true after the
        // functions execution:
        //      x = self.x
        //      y = self.y
        //      z = self.z

        // Cache self's coordinates on stack.
        uint256 x1 = self.x;
        uint256 y1 = self.y;
        uint256 z1 = self.z;

        // Compute z1_2 = z1²     (mod P)
        //              = z1 * z1 (mod P)
        uint256 z1_2 = mulmod(z1, z1, _P);

        // Compute h = u        - x1       (mod P)
        //           = u        + (P - x1) (mod P)
        //           = x2 * z1² + (P - x1) (mod P)
        //
        // Unchecked because the only protected operation performed is P - x1
        // where x1 is guaranteed by the caller to be an x coordinate belonging
        // to a point on the curve, i.e. being less than P.
        uint256 h;
        unchecked {
            h = addmod(mulmod(p.x, z1_2, _P), _P - x1, _P);
        }

        // Compute h_2 = h²    (mod P)
        //             = h * h (mod P)
        uint256 h_2 = mulmod(h, h, _P);

        // Compute i = 4 * h² (mod P)
        uint256 i = mulmod(4, h_2, _P);

        // Compute z = (z1 + h)² - z1²       - h²       (mod P)
        //           = (z1 + h)² - z1²       + (P - h²) (mod P)
        //           = (z1 + h)² + (P - z1²) + (P - h²) (mod P)
        //             ╰───────╯   ╰───────╯   ╰──────╯
        //               left         mid       right
        //
        // Unchecked because the only protected operations performed are
        // subtractions from P where the subtrahend is the result of a (mod P)
        // computation, i.e. the subtrahend being guaranteed to be less than P.
        unchecked {
            uint256 left = mulmod(addmod(z1, h, _P), addmod(z1, h, _P), _P);
            uint256 mid = _P - z1_2;
            uint256 right = _P - h_2;

            self.z = addmod(left, addmod(mid, right, _P), _P);
        }

        // Compute v = x1 * i (mod P)
        uint256 v = mulmod(x1, i, _P);

        // Compute j = h * i (mod P)
        uint256 j = mulmod(h, i, _P);

        // Compute r = 2 * (s               - y1)       (mod P)
        //           = 2 * (s               + (P - y1)) (mod P)
        //           = 2 * ((y2 * z1³)      + (P - y1)) (mod P)
        //           = 2 * ((y2 * z1² * z1) + (P - y1)) (mod P)
        //
        // Unchecked because the only protected operation performed is P - y1
        // where y1 is guaranteed by the caller to be an y coordinate belonging
        // to a point on the curve, i.e. being less than P.
        uint256 r;
        unchecked {
            r = mulmod(2, addmod(mulmod(p.y, mulmod(z1_2, z1, _P), _P), _P - y1, _P), _P);
        }

        // Compute x = r² - j - (2 * v)             (mod P)
        //           = r² - j + (P - (2 * v))       (mod P)
        //           = r² + (P - j) + (P - (2 * v)) (mod P)
        //                  ╰─────╯   ╰───────────╯
        //                    mid         right
        //
        // Unchecked because the only protected operations performed are
        // subtractions from P where the subtrahend is the result of a (mod P)
        // computation, i.e. the subtrahend being guaranteed to be less than P.
        unchecked {
            uint256 r_2 = mulmod(r, r, _P);
            uint256 mid = _P - j;
            uint256 right = _P - mulmod(2, v, _P);

            self.x = addmod(r_2, addmod(mid, right, _P), _P);
        }

        // Compute y = (r * (v - x))       - (2 * y1 * j)       (mod P)
        //           = (r * (v - x))       + (P - (2 * y1 * j)) (mod P)
        //           = (r * (v + (P - x))) + (P - (2 * y1 * j)) (mod P)
        //             ╰─────────────────╯   ╰────────────────╯
        //                    left                 right
        //
        // Unchecked because the only protected operations performed are
        // subtractions from P where the subtrahend is the result of a (mod P)
        // computation, i.e. the subtrahend being guaranteed to be less than P.
        unchecked {
            uint256 left = mulmod(r, addmod(v, _P - self.x, _P), _P);
            uint256 right = _P - mulmod(2, mulmod(y1, j, _P), _P);

            self.y = addmod(left, right, _P);
        }
    }

    /// @dev Adds two affine points, treating `(0, 0)` as the point at infinity.
    ///
    ///      The mixed madd-2007-bl formula used by `addAffinePointToXYZ` is only
    ///      defined for two distinct, non-infinite points: it degenerates to
    ///      `z = 0` whenever the operands share an x coordinate, and it silently
    ///      produces an off-curve result when either operand is the `(0, 0)`
    ///      infinity sentinel. This wrapper handles all three exceptional cases:
    ///      identity operands, doubling (`a == b`) and mutual negation
    ///      (`a == -b`, which yields infinity).
    ///
    ///      It is the caller's responsibility to ensure both operands are either
    ///      the infinity sentinel or on the curve.
    function addAffine(Point memory a, Point memory b) internal view returns (Point memory) {
        if (a.isZeroPoint()) return Point({x: b.x, y: b.y});
        if (b.isZeroPoint()) return Point({x: a.x, y: a.y});

        // On secp256k1 a shared x coordinate means `b == a` or `b == -a`.
        if (a.x == b.x) {
            if (a.y != b.y) return ZERO_POINT();

            JacobianPoint memory doubled = a.toJacobian();
            doubled.jacobianDouble();
            return toAffineModexpXYZ(doubled.x, doubled.y, doubled.z);
        }

        (uint256 x, uint256 y, uint256 z) = addAffinePointToXYZ(a.x, a.y, 1, b.x, b.y);
        return toAffineModexpXYZ(x, y, z);
    }

    /// @dev Field modulus p for the short Weierstrass curve (public for companion libraries).
    function fieldP() internal pure returns (uint256) {
        return _P;
    }

    /// @dev Jacobian point doubling (a = 0), dbl-2009-l; mutates `self` in place.
    function jacobianDouble(JacobianPoint memory self) internal pure {
        uint256 z1 = self.z;
        if (z1 == 0) {
            return;
        }
        uint256 x1 = self.x;
        uint256 y1 = self.y;
        unchecked {
            uint256 a = mulmod(x1, x1, _P);
            uint256 b = mulmod(y1, y1, _P);
            uint256 c = mulmod(b, b, _P);
            uint256 d = addmod(x1, b, _P);
            d = mulmod(d, d, _P);
            d = addmod(addmod(d, _P - a, _P), _P - c, _P);
            d = mulmod(2, d, _P);
            uint256 e = mulmod(3, a, _P);
            uint256 f = mulmod(e, e, _P);
            uint256 x3 = addmod(f, _P - mulmod(2, d, _P), _P);
            uint256 y3 = mulmod(e, addmod(d, _P - x3, _P), _P);
            y3 = addmod(y3, _P - mulmod(8, c, _P), _P);
            uint256 z3 = mulmod(2, mulmod(y1, z1, _P), _P);
            self.x = x3;
            self.y = y3;
            self.z = z3;
        }
    }

    /// @dev Scalar multiplication in the secp256k1 group (affine non-zero point, scalar mod order domain handled by caller).
    function mulAffine(Point memory p, uint256 scalar) internal pure returns (Point memory) {
        if (scalar == 0 || isZeroPoint(p)) {
            return ZERO_POINT();
        }
        uint256 msb = 255;
        while (msb > 0 && ((scalar >> msb) & 1) == 0) {
            unchecked {
                msb--;
            }
        }
        JacobianPoint memory r = p.toJacobian();
        unchecked {
            for (uint256 i = msb; i > 0;) {
                --i;
                jacobianDouble(r);
                if (((scalar >> i) & 1) == 1) {
                    addAffinePoint(r, p);
                }
            }
        }
        return r.toAffine();
    }

    /// @notice Decompress 33-byte compressed key into (x, y) coordinates
    /// @param comp Compressed pubkey: 0x02/0x03 prefix + 32-byte x
    /// @return point Struct with affine coordinates
    function decompress(bytes memory comp) internal view returns (Point memory point) {
        if (comp.length != 33) revert InvalidCompressedPubkeyLength();
        uint8 prefix = uint8(comp[0]);
        if (prefix != 0x02 && prefix != 0x03) revert InvalidCompressedPubkeyPrefix();

        uint256 x;
        assembly {
            // load 32 bytes starting at comp+0x21 (first byte of X)
            x := mload(add(comp, 0x21))
        }
        if (x >= _P) revert CompressedPubkeyXOutOfRange();

        // y = sqrt(x^3+7) mod p
        uint256 xx = mulmod(x, x, _P);
        uint256 rhs = addmod(mulmod(xx, x, _P), _B, _P);
        uint256 y = _modExp(rhs, EXPONENT, _P);

        // pick root matching prefix (0x02 even, 0x03 odd)
        if ((y & 1) != (prefix & 1)) y = _P - y;
        if (rhs == 0 && prefix != 0x02) revert InvalidZeroParity();

        point = Point(x, y);
    }

    /// @notice Compress affine point into 33-byte form (0x02/0x03 + X)
    /// @dev Validates point is on secp256k1 curve
    function compress(Point memory p) internal pure returns (bytes memory comp) {
        if (p.x >= _P || p.y >= _P) revert CoordinatesOutOfRange();
        // y^2 == x^3 + 7 mod p
        uint256 lhs = mulmod(p.y, p.y, _P);
        uint256 rhs = addmod(mulmod(mulmod(p.x, p.x, _P), p.x, _P), _B, _P);
        if (lhs != rhs) revert PointNotOnCurve();

        bytes1 prefix = (p.y & 1 == 0) ? bytes1(0x02) : bytes1(0x03);
        // ← avoids any ambiguity with mstore offsets
        comp = abi.encodePacked(prefix, bytes32(p.x));
    }

    // -- Private Helpers --

    /// @dev Returns the modular inverse of `x` for modulo `_P`.
    ///
    ///      It is the caller's responsibility to ensure `x` is less than `_P`!
    ///
    ///      The modular inverse of `x` is x⁻¹ such that x * x⁻¹ ≡ 1 (mod P).
    ///
    /// @dev Modified from Jordi Baylina's [ecsol](https://github.com/jbaylina/ecsol/blob/c2256afad126b7500e6f879a9369b100e47d435d/ec.sol#L51-L67).
    ///
    /// @custom:invariant Reverts iff out of gas.
    /// @custom:invariant Does not run into an infinite loop.
    function _invMod(uint256 x) private pure returns (uint256) {
        uint256 t;
        uint256 q;
        uint256 newT = 1;
        uint256 r = _P;

        assembly ("memory-safe") {
            // Implemented in assembly to circumvent division-by-zero
            // and over-/underflow protection.
            //
            // Functionally equivalent Solidity code:
            //      while (x != 0) {
            //          q = r / x;
            //          (t, newT) = (newT, addmod(t, (_P - mulmod(q, newT, _P)), _P));
            //          (r, x) = (x, r - (q * x));
            //      }
            //
            // For the division r / x, x is guaranteed to not be zero via the
            // loop condition.
            //
            // The subtraction of form P - mulmod(_, _, P) is guaranteed to not
            // underflow due to the subtrahend being a (mod P) result,
            // i.e. the subtrahend being guaranteed to be less than P.
            //
            // The subterm q * x is guaranteed to not overflow because
            // q * x ≤ r due to q = ⎣r / x⎦.
            //
            // The term r - (q * x) is guaranteed to not underflow because
            // q * x ≤ r and therefore r - (q * x) ≥ 0.
            for {} x {} {
                q := div(r, x)

                let tmp := t
                t := newT
                newT := addmod(tmp, sub(_P, mulmod(q, newT, _P)), _P)

                tmp := r
                r := x
                x := sub(tmp, mul(q, x))
            }
        }

        return t;
    }

    function _modExp(uint256 base, uint256 exp, uint256 mod) private view returns (uint256 result) {
        // EIP-198 expects: |len(b)|len(e)|len(m)| b | e | m | — six 32-byte words, no extra allocation.
        uint256[6] memory input;
        input[0] = 32; // len(b)
        input[1] = 32; // len(e)
        input[2] = 32; // len(m)
        input[3] = base;
        input[4] = exp;
        input[5] = mod;

        uint256[1] memory out;
        bool ok;
        assembly ("memory-safe") {
            ok := staticcall(gas(), 5, input, 192, out, 32)
        }
        if (!ok) revert ModExpFailed();
        result = out[0];
        if (result >= mod) revert ModExpResultOutOfRange();
    }
}
