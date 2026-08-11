// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/// @title LibSecp256k1
/// @notice secp256k1 helpers for Schnorr aggregate-key math; not a general EC library.
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

    uint256 private constant _B = 7;
    uint256 private constant _P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;
    uint256 private constant EXPONENT = (_P + 1) >> 2;

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

    function ZERO_POINT() internal pure returns (Point memory) {
        return Point({x: 0, y: 0});
    }

    // -- (Affine) Point --
    struct Point {
        uint256 x;
        uint256 y;
    }

    /// @dev Returns the Ethereum address of `self`.
    function toAddress(Point memory self) internal pure returns (address) {
        address addr;
        assembly ("memory-safe") {
            addr := and(keccak256(self, 0x40), ADDRESS_MASK)
        }
        return addr;
    }

    /// @dev Derive `address(privKey · G)` via one `ecrecover` (registry-v2 §6.1).
    ///      Sets `r = Gx`, `v` from `Gy` parity, `h = 0`, `s = privKey · Gx mod Q`.
    function pubkeyAddressFromScalar(uint256 privKey) internal pure returns (address) {
        if (privKey == 0 || privKey >= Q()) return address(0);
        Point memory g = G();
        bytes32 r = bytes32(g.x);
        // Gy of secp256k1 G is even → v = 27.
        uint8 v = uint8(27 + (g.y & 1));
        bytes32 s = bytes32(mulmod(privKey, g.x, Q()));
        return ecrecover(bytes32(0), v, r, s);
    }

    function toJacobian(Point memory self) internal pure returns (JacobianPoint memory) {
        return JacobianPoint({x: self.x, y: self.y, z: 1});
    }

    function isZeroPoint(Point memory self) internal pure returns (bool) {
        return (self.x | self.y) == 0;
    }

    function isOnCurve(Point memory self) internal pure returns (bool) {
        uint256 left = mulmod(self.y, self.y, _P);
        uint256 right = addmod(mulmod(self.x, mulmod(self.x, self.x, _P), _P), _B, _P);
        return left == right;
    }

    function yParity(Point memory self) internal pure returns (uint256) {
        return self.y & 1;
    }

    struct JacobianPoint {
        uint256 x;
        uint256 y;
        uint256 z;
    }

    function toAffine(JacobianPoint memory self) internal view returns (Point memory) {
        return toAffineModexpXYZ(self.x, self.y, self.z);
    }

    /// @dev Scalar-input variant of `toAffine`. Accepts the Jacobian coordinates
    ///      as plain scalars so the caller can avoid allocating a JacobianPoint memory
    ///      struct and the three MLOADs that would follow.
    function toAffineModexpXYZ(uint256 jx, uint256 jy, uint256 jz) internal view returns (Point memory result) {
        if (jz == 1) {
            return Point({x: jx, y: jy});
        }
        uint256 zInv = _modExp(jz, _P - 2, _P);
        uint256 zInv2 = mulmod(zInv, zInv, _P);
        result.x = mulmod(jx, zInv2, _P);
        result.y = mulmod(jy, mulmod(zInv, zInv2, _P), _P);
    }

    /// @dev Mixed Jacobian+Affine EC addition (madd-2007-bl, z₂=1), the canonical
    ///      implementation in this library. Inputs and outputs are plain scalars rather
    ///      than memory structs, which avoids the 3-MLOAD / 3-MSTORE round-trip a struct
    ///      form incurs per call and lets via-ir keep the accumulator in Yul stack slots.
    ///
    ///      Addition formula, with (x1, y1, z1) = Jacobian and (x2, y2) = affine:
    ///          u = x2 * z1²                v = x1 * i
    ///          s = y2 * z1³                j = h * i
    ///          h = u - x1                  r = 2 * (s - y1)
    ///          i = 4 * h²
    ///          x3 = r² - j - 2v            y3 = r * (v - x3) - 2 * y1 * j
    ///          z3 = (z1 + h)² - z1² - h²
    ///      all mod P.
    ///
    ///      Negation is written as sub(P, x); this is safe because every intermediate
    ///      produced by mulmod/addmod lies in [0, P-1], so P - x ≥ 1.
    ///
    ///      Reference: https://hyperelliptic.org/EFD/g1p/auto-shortw-jacobian.html#addition-madd-2007-bl
    function addAffinePointToXYZ(uint256 jx, uint256 jy, uint256 jz, uint256 px, uint256 py)
        internal
        pure
        returns (uint256 nax, uint256 nay, uint256 naz)
    {
        assembly ("memory-safe") {
            let P := 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
            let z2 := mulmod(jz, jz, P)
            let z3 := mulmod(z2, jz, P)
            let h := addmod(mulmod(px, z2, P), sub(P, jx), P)
            let h2 := mulmod(h, h, P)
            let i2 := mulmod(4, h2, P)
            let v := mulmod(jx, i2, P)
            let j := mulmod(h, i2, P)
            let r := mulmod(2, addmod(mulmod(py, z3, P), sub(P, jy), P), P)
            let azh := addmod(jz, h, P)
            naz := addmod(mulmod(azh, azh, P), addmod(sub(P, z2), sub(P, h2), P), P)
            nax := addmod(mulmod(r, r, P), addmod(sub(P, j), sub(P, mulmod(2, v, P)), P), P)
            nay := addmod(mulmod(r, addmod(v, sub(P, nax), P), P), sub(P, mulmod(2, mulmod(jy, j, P), P)), P)
        }
    }

    /// @dev Struct form of `addAffinePointToXYZ`; mutates `self` in place.
    function addAffinePoint(JacobianPoint memory self, Point memory p) internal pure {
        (self.x, self.y, self.z) = addAffinePointToXYZ(self.x, self.y, self.z, p.x, p.y);
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
    function mulAffine(Point memory p, uint256 scalar) internal view returns (Point memory) {
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

    function decompress(bytes memory comp) internal view returns (Point memory point) {
        if (comp.length != 33) revert InvalidCompressedPubkeyLength();
        uint8 prefix = uint8(comp[0]);
        if (prefix != 0x02 && prefix != 0x03) revert InvalidCompressedPubkeyPrefix();

        uint256 x;
        assembly ("memory-safe") {
            x := mload(add(comp, 0x21))
        }
        if (x >= _P) revert CompressedPubkeyXOutOfRange();

        // y² = x³ + 7 (mod P)
        uint256 rhs = addmod(mulmod(mulmod(x, x, _P), x, _P), _B, _P);
        if (rhs == 0 && prefix != 0x02) revert InvalidZeroParity();

        uint256 y = _modExp(rhs, EXPONENT, _P);
        // `_modExp` yields a square root only when `rhs` is a quadratic residue; otherwise the
        // candidate squares to -rhs and no curve point carries this x-coordinate.
        if (mulmod(y, y, _P) != rhs) revert PointNotOnCurve();
        if ((y & 1) != (prefix & 1)) y = _P - y;

        point = Point(x, y);
    }

    /// @notice Compress affine point into 33-byte form (0x02/0x03 + X)
    function compress(Point memory p) internal pure returns (bytes memory comp) {
        if (p.x >= _P || p.y >= _P) revert CoordinatesOutOfRange();
        uint256 lhs = mulmod(p.y, p.y, _P);
        uint256 rhs = addmod(mulmod(mulmod(p.x, p.x, _P), p.x, _P), _B, _P);
        if (lhs != rhs) revert PointNotOnCurve();

        bytes1 prefix = (p.y & 1 == 0) ? bytes1(0x02) : bytes1(0x03);
        comp = abi.encodePacked(prefix, bytes32(p.x));
    }

    function _modExp(uint256 base, uint256 exp, uint256 mod) private view returns (uint256 result) {
        uint256[6] memory input;
        input[0] = 32;
        input[1] = 32;
        input[2] = 32;
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
