// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.31;

import {LibSecp256k1} from "./LibSecp256k1.sol";

/// @title LibMuSig2KeyAgg
/// @notice MuSig2-style key delinearization: L = H(sorted X_i), a_i = H(domain||L||X_i), X_agg = Σ a_i·X_i.
library LibMuSig2KeyAgg {
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.JacobianPoint;

    /// @dev Lexicographic compare of uncompressed encodings (x then y, big-endian uint order).
    function _lexCmp(LibSecp256k1.Point memory a, LibSecp256k1.Point memory b) private pure returns (int256) {
        if (a.x < b.x) return -1;
        if (a.x > b.x) return 1;
        if (a.y < b.y) return -1;
        if (a.y > b.y) return 1;
        return 0;
    }

    /// @dev Insertion sort ascending by (x, y).
    function _sortPubkeys(LibSecp256k1.Point[] memory pts) private pure returns (LibSecp256k1.Point[] memory sorted) {
        uint256 n = pts.length;
        sorted = new LibSecp256k1.Point[](n);
        for (uint256 i; i < n; ++i) {
            sorted[i] = pts[i];
        }
        for (uint256 i = 1; i < n; ++i) {
            LibSecp256k1.Point memory key = sorted[i];
            uint256 j = i;
            while (j > 0 && _lexCmp(sorted[j - 1], key) > 0) {
                sorted[j] = sorted[j - 1];
                unchecked {
                    --j;
                }
            }
            sorted[j] = key;
        }
    }

    /// @dev L = keccak256(X_{(1)} || … || X_{(n)}) with pubkeys sorted by 64-byte encoding.
    function _hashPubkeyList(LibSecp256k1.Point[] memory sorted) private pure returns (bytes32) {
        bytes memory buf;
        uint256 n = sorted.length;
        for (uint256 i; i < n; ++i) {
            buf = abi.encodePacked(buf, bytes32(sorted[i].x), bytes32(sorted[i].y));
        }
        return keccak256(buf);
    }

    function _coeffModQ(bytes32 L, LibSecp256k1.Point memory x) private pure returns (uint256) {
        uint256 a = uint256(
            keccak256(abi.encodePacked(bytes("MOLPHA_MUSIG2_COEFF_V1"), bytes32(L), bytes32(x.x), bytes32(x.y)))
        ) % LibSecp256k1.Q();
        if (a == 0) {
            return 1;
        }
        return a;
    }

    /// @notice Aggregate public key for a signing coalition (each key appears once).
    function aggregateKeys(LibSecp256k1.Point[] memory participantPubkeys)
        internal
        pure
        returns (LibSecp256k1.Point memory)
    {
        uint256 k = participantPubkeys.length;
        if (k == 0) {
            return LibSecp256k1.ZERO_POINT();
        }
        LibSecp256k1.Point[] memory sorted = _sortPubkeys(participantPubkeys);
        bytes32 L = _hashPubkeyList(sorted);

        LibSecp256k1.JacobianPoint memory acc;
        bool init;
        for (uint256 i; i < k; ++i) {
            LibSecp256k1.Point memory xi = participantPubkeys[i];
            uint256 ai = _coeffModQ(L, xi);
            LibSecp256k1.Point memory term = LibSecp256k1.mulAffine(xi, ai);
            if (!init) {
                acc = term.toJacobian();
                init = true;
            } else {
                acc.addAffinePoint(term);
            }
        }
        return acc.toAffine();
    }

    /// @dev Registry layout: index 0 unused; active nodes at 1 .. length-1.
    function aggregateRegistryKeys(LibSecp256k1.Point[] memory registryWithPlaceholder)
        internal
        pure
        returns (LibSecp256k1.Point memory)
    {
        uint256 len = registryWithPlaceholder.length;
        if (len <= 1) {
            return LibSecp256k1.ZERO_POINT();
        }
        LibSecp256k1.Point[] memory pts = new LibSecp256k1.Point[](len - 1);
        for (uint256 i = 1; i < len; ++i) {
            pts[i - 1] = registryWithPlaceholder[i];
        }
        return aggregateKeys(pts);
    }

    /// @notice Per-node effective keys P'_i = a_i(L_reg)·X_i and full aggregate (Intent C).
    /// @dev L_reg is derived from the sorted full registered set (same as aggregateRegistryKeys).
    ///      Index 0 is ZERO_POINT; index i (1-based) matches registryWithPlaceholder[i].
    function computeEffectiveKeysAndAggregate(LibSecp256k1.Point[] memory registryWithPlaceholder)
        internal
        pure
        returns (LibSecp256k1.Point[] memory effectiveKeys, LibSecp256k1.Point memory muSigXAgg)
    {
        uint256 len = registryWithPlaceholder.length;
        effectiveKeys = new LibSecp256k1.Point[](len);
        effectiveKeys[0] = LibSecp256k1.ZERO_POINT();

        if (len <= 1) {
            muSigXAgg = LibSecp256k1.ZERO_POINT();
            return (effectiveKeys, muSigXAgg);
        }

        LibSecp256k1.Point[] memory pts = new LibSecp256k1.Point[](len - 1);
        for (uint256 i = 1; i < len; ++i) {
            pts[i - 1] = registryWithPlaceholder[i];
        }
        LibSecp256k1.Point[] memory sorted = _sortPubkeys(pts);
        bytes32 Lreg = _hashPubkeyList(sorted);

        LibSecp256k1.JacobianPoint memory acc;
        bool init;
        for (uint256 i = 1; i < len; ++i) {
            LibSecp256k1.Point memory xi = registryWithPlaceholder[i];
            uint256 ai = _coeffModQ(Lreg, xi);
            LibSecp256k1.Point memory term = LibSecp256k1.mulAffine(xi, ai);
            effectiveKeys[i] = term;
            if (!init) {
                acc = term.toJacobian();
                init = true;
            } else {
                acc.addAffinePoint(term);
            }
        }
        muSigXAgg = acc.toAffine();
    }
}
