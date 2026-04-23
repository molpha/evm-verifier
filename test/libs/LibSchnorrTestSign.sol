// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";
import {LibSchnorr} from "../../src/libs/LibSchnorr.sol";

/// @title LibSchnorrTestSign
///      signature scalar s = k + e·x (mod Q) where P = [x]G.
library LibSchnorrTestSign {
    using LibSecp256k1 for LibSecp256k1.Point;

    /// @dev MuSig2 coefficient a_i = H("MOLPHA_MUSIG2_COEFF_V1" ‖ L ‖ X_i) mod Q (same as `LibMuSig2KeyAgg._coeffModQ`).
    function _coeffModQ(bytes32 L, LibSecp256k1.Point memory x) private pure returns (uint256) {
        uint256 a = uint256(keccak256(abi.encodePacked(bytes("MOLPHA_MUSIG2_COEFF_V1"), L, bytes32(x.x), bytes32(x.y))))
            % LibSecp256k1.Q();
        if (a == 0) {
            return 1;
        }
        return a;
    }

    /// @dev L = keccak256(X_{(1)} ‖ …) with a single pubkey (sorted list hash).
    function _hashSinglePubkeyList(LibSecp256k1.Point memory p) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(bytes32(p.x), bytes32(p.y)));
    }

    /// @dev Sort pubkeys lexicographically (same as LibMuSig2KeyAgg._sortPubkeys).
    function _sortPubkeys(LibSecp256k1.Point[] memory pts) private pure returns (LibSecp256k1.Point[] memory sorted) {
        uint256 n = pts.length;
        sorted = new LibSecp256k1.Point[](n);
        for (uint256 i; i < n; ++i) {
            sorted[i] = pts[i];
        }
        for (uint256 i = 1; i < n; ++i) {
            LibSecp256k1.Point memory key = sorted[i];
            uint256 j = i;
            while (j > 0 && (sorted[j - 1].x > key.x || (sorted[j - 1].x == key.x && sorted[j - 1].y > key.y))) {
                sorted[j] = sorted[j - 1];
                unchecked {
                    --j;
                }
            }
            sorted[j] = key;
        }
    }

    /// @dev L_reg = keccak256(sorted pubkeys as 32-byte x ‖ 32-byte y each).
    function _hashPubkeyList(LibSecp256k1.Point[] memory sorted) private pure returns (bytes32) {
        bytes memory buf;
        for (uint256 i; i < sorted.length; ++i) {
            buf = abi.encodePacked(buf, bytes32(sorted[i].x), bytes32(sorted[i].y));
        }
        return keccak256(buf);
    }

    /// @notice Effective private key for `pubkey`/`privateKey` under registry-wide L (Intent C / NodeRegistry).
    /// @param allRegistryPubkeys Active node pubkeys only (no placeholder); order arbitrary.
    function effectiveSecretRegistryL(
        LibSecp256k1.Point[] memory allRegistryPubkeys,
        LibSecp256k1.Point memory pubkey,
        uint256 privateKey
    ) internal pure returns (uint256 skEff) {
        LibSecp256k1.Point[] memory sorted = _sortPubkeys(allRegistryPubkeys);
        bytes32 Lreg = _hashPubkeyList(sorted);
        uint256 a = _coeffModQ(Lreg, pubkey);
        skEff = mulmod(a, privateKey, LibSecp256k1.Q());
    }

    /// @notice Scalar x such that `[x]G` matches `LibMuSig2KeyAgg.aggregateKeys` for a one-node coalition `{P1}`.
    /// @dev Here `d1` is the secp256k1 scalar with `P1 = [d1]G`; aggregate pubkey is `[a1·d1]G` with `a1` the MuSig2 coeff.
    function effectiveSecretSingleSigner(LibSecp256k1.Point memory p1, uint256 d1)
        internal
        pure
        returns (uint256 skEff)
    {
        bytes32 L = _hashSinglePubkeyList(p1);
        uint256 a1 = _coeffModQ(L, p1);
        skEff = mulmod(a1, d1, LibSecp256k1.Q());
    }

    /// @notice Produce `(signature, commitment)` for `pubKey` / `privateKey` / `message`.
    /// @param privateKey Discrete log of `pubKey` on secp256k1: `[privateKey]G == pubKey`.
    /// @param nonceSalt Varies the deterministic nonce search if the first attempts fail rare edge cases.
    function sign(LibSecp256k1.Point memory pubKey, uint256 privateKey, bytes32 message, uint256 nonceSalt)
        internal
        pure
        returns (bytes32 signature, address commitment)
    {
        uint256 Q = LibSecp256k1.Q();
        uint256 k;
        LibSecp256k1.Point memory R;
        uint256 e;
        uint256 s;

        for (uint256 attempt; attempt < 128; ++attempt) {
            k = (
                uint256(
                    keccak256(abi.encodePacked("SCHNORR_TEST_NONCE", nonceSalt, attempt, message, pubKey.x, pubKey.y))
                ) % (Q - 1)
            ) + 1;

            R = LibSecp256k1.mulAffine(LibSecp256k1.G(), k);
            commitment = R.toAddress();
            if (commitment == address(0)) {
                continue;
            }

            e = uint256(keccak256(abi.encodePacked(pubKey.x, uint8(pubKey.yParity()), message, commitment))) % Q;

            s = addmod(k, mulmod(e, privateKey, Q), Q);
            if (s == 0) {
                continue;
            }

            signature = bytes32(s);
            if (uint256(signature) >= Q) {
                continue;
            }

            if (LibSchnorr.verifySignature(pubKey, message, signature, commitment)) {
                return (signature, commitment);
            }
        }
        revert("LibSchnorrTestSign: could not produce signature");
    }
}
