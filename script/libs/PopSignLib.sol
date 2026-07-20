// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.31;

import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";
import {LibSchnorr} from "../../src/libs/LibSchnorr.sol";

/// @title PopSignLib
/// @notice Schnorr signing helper for validator node registration PoP proofs in admin scripts.
library PopSignLib {
    using LibSecp256k1 for LibSecp256k1.Point;

    error CouldNotProduceSignature();

    /// @notice Produce `(signature, commitment)` for `pubKey` / `privateKey` / `message`.
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
            k =
                (uint256(
                            keccak256(
                                abi.encodePacked("SCHNORR_TEST_NONCE", nonceSalt, attempt, message, pubKey.x, pubKey.y)
                            )
                        )
                        % (Q - 1)) + 1;

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
        revert CouldNotProduceSignature();
    }
}
