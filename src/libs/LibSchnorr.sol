// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {ECDSA} from "solady/utils/ECDSA.sol";
import {LibSecp256k1} from "./LibSecp256k1.sol";

/// @title LibSchnorr
/// @notice Schnorr signature verification on secp256k1
library LibSchnorr {
    using LibSecp256k1 for LibSecp256k1.Point;
    using ECDSA for bytes32;

    /// @dev Caller must ensure `pubKey` is on-curve and inputs are in range.
    ///      Uses `tryRecover` rather than `recover`: a degenerate `ecrecover` input must
    ///      report "not verified" rather than revert, since `Verifier.verify` never reverts.
    function verifySignatureTrusted(
        LibSecp256k1.Point memory pubKey,
        bytes32 message,
        bytes32 signature,
        address commitment
    ) internal view returns (bool) {
        uint256 q = LibSecp256k1.Q();
        uint256 px = pubKey.x;
        uint8 parity = uint8(pubKey.yParity());
        uint256 challenge = uint256(keccak256(abi.encodePacked(px, parity, message, commitment))) % q;

        // Re-express `s·G == R + e·P` as an `ecrecover` over the point with x-coordinate `px`.
        bytes32 msgHash;
        bytes32 s;
        unchecked {
            msgHash = bytes32(q - mulmod(uint256(signature), px, q));
            s = bytes32(q - mulmod(challenge, px, q));
        }

        return commitment == msgHash.tryRecover(parity + 27, bytes32(px), s);
    }

    function verifySignature(LibSecp256k1.Point memory pubKey, bytes32 message, bytes32 signature, address commitment)
        internal
        view
        returns (bool)
    {
        if (signature == 0 || commitment == address(0)) {
            return false;
        }
        if (!pubKey.isOnCurve()) {
            return false;
        }
        if (uint256(signature) >= LibSecp256k1.Q()) {
            return false;
        }

        return verifySignatureTrusted(pubKey, message, signature, commitment);
    }
}
