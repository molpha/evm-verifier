// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.31;

import {IVerifier} from "../interfaces/IVerifier.sol";
import {LibSchnorr} from "../libs/LibSchnorr.sol";
import {LibSecp256k1} from "../libs/LibSecp256k1.sol";

/// @title MolphaSigLib
/// @notice Stateless Schnorr signing helpers for tests: deterministic keys, proof of possession,
///         aggregate signing, and the attestation builder behind `MolphaTestSigner`.
/// @dev Test-only. Never deploy this against real keys — the nonce is deterministic and public.
///
///      Uses no cheatcodes, so it does not depend on forge-std and works from any contract.
///      Pinned to `^0.8.31` because it reaches into `LibSecp256k1`; consumers on older compilers
///      should use `MockVerifier` instead.
///
///      The message encoding below intentionally RE-IMPLEMENTS the wire format
///      rather than delegating to `VerifierLib`. That independence is what makes
///      `test/integration/MessageFormatSpec.t.sol` an actual check instead of a tautology.
///      Keep them in sync with `docs/message-format.md`, not with `VerifierLib`.
library MolphaSigLib {
    using LibSecp256k1 for LibSecp256k1.Point;

    error CouldNotProduceSignature();
    error InsufficientSelectedSigners();
    error EmptySignerSet();

    bytes32 internal constant POP_DOMAIN = keccak256("MOLPHA_VERIFIER_V1");
    bytes32 internal constant MESSAGE_PREFIX = keccak256("MOLPHA_MESSAGE_V1");

    /// @notice Deterministic test private key for a 1-based slot.
    /// @dev The literal domain string and the `% (Q-1) + 1` reduction are load-bearing: every node
    ///      address and registry root in the existing suite derives from them.
    function testSecret(uint256 slot) internal pure returns (uint256) {
        return (uint256(keccak256(abi.encodePacked("MOLPHA_VERIFIER_TEST_KEY", slot))) % (LibSecp256k1.Q() - 1)) + 1;
    }

    /// @notice Produce `(signature, commitment)` for `pubKey` / `privateKey` / `message`.
    /// @param privateKey Discrete log of `pubKey` on secp256k1: `[privateKey]G == pubKey`.
    /// @param nonceSalt Varies the deterministic nonce search if the first attempts fail rare edge cases.
    function sign(LibSecp256k1.Point memory pubKey, uint256 privateKey, bytes32 digest, uint256 nonceSalt)
        internal
        view
        returns (bytes32 signature, address commitment)
    {
        uint256 q = LibSecp256k1.Q();
        uint256 k;
        LibSecp256k1.Point memory r;
        uint256 e;
        uint256 s;

        for (uint256 attempt; attempt < 128; ++attempt) {
            k =
                (uint256(
                            keccak256(
                                abi.encodePacked("SCHNORR_TEST_NONCE", nonceSalt, attempt, digest, pubKey.x, pubKey.y)
                            )
                        )
                        % (q - 1)) + 1;

            r = LibSecp256k1.mulAffine(LibSecp256k1.G(), k);
            commitment = r.toAddress();
            if (commitment == address(0)) continue;

            e = uint256(keccak256(abi.encodePacked(pubKey.x, uint8(pubKey.yParity()), digest, commitment))) % q;

            s = addmod(k, mulmod(e, privateKey, q), q);
            if (s == 0) continue;

            signature = bytes32(s);
            if (uint256(signature) >= q) continue;

            if (LibSchnorr.verifySignature(pubKey, digest, signature, commitment)) {
                return (signature, commitment);
            }
        }
        revert CouldNotProduceSignature();
    }

    /// @notice Schnorr proof of possession binding a key to one verifier deployment.
    function proofOfPossession(address verifierAddress, bytes memory compressedPubkey, uint256 secret)
        internal
        view
        returns (IVerifier.SchnorrProof memory proof)
    {
        bytes32 digest = keccak256(abi.encodePacked(POP_DOMAIN, verifierAddress, compressedPubkey));
        LibSecp256k1.Point memory pubkey = LibSecp256k1.decompress(compressedPubkey);
        (bytes32 signature, address commitment) = sign(pubkey, secret, digest, 0);
        proof = IVerifier.SchnorrProof({signature: signature, commitment: commitment});
    }

    /// @notice The digest the aggregate signature is produced over.
    function message(IVerifier.AttestationPayload memory payload, uint256 signersBitmap)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                MESSAGE_PREFIX,
                payload.value,
                payload.sourceId,
                payload.registryVersion,
                payload.signaturesRequired,
                payload.timestamp,
                signersBitmap
            )
        );
    }

    /// @notice Take the lowest `count` set bits of `bitmap` as 0-based key slots.
    function pickSignerIndices(uint256 bitmap, uint256 registeredNodes, uint256 count)
        internal
        pure
        returns (uint256[] memory indices)
    {
        indices = new uint256[](count);
        uint256 found;
        for (uint256 position; position < registeredNodes; ++position) {
            if (bitmap & (uint256(1) << position) == 0) continue;
            indices[found] = position;
            unchecked {
                ++found;
            }
            if (found == count) return indices;
        }
        revert InsufficientSelectedSigners();
    }

    /// @notice Sum the selected public keys into the coalition key.
    function sumPubkeys(LibSecp256k1.Point[] memory pubkeys, uint256[] memory indices)
        internal
        view
        returns (LibSecp256k1.Point memory aggregate)
    {
        if (indices.length == 0) revert EmptySignerSet();
        aggregate = pubkeys[indices[0]];
        for (uint256 i = 1; i < indices.length; ++i) {
            LibSecp256k1.Point memory next = pubkeys[indices[i]];
            (uint256 x, uint256 y, uint256 z) =
                LibSecp256k1.addAffinePointToXYZ(aggregate.x, aggregate.y, 1, next.x, next.y);
            aggregate = LibSecp256k1.toAffineModexpXYZ(x, y, z);
        }
    }

    /// @notice Sum the selected secrets mod Q, mirroring `sumPubkeys`.
    function sumSecrets(uint256[] memory secrets, uint256[] memory indices)
        internal
        pure
        returns (uint256 aggregateSecret)
    {
        for (uint256 i; i < indices.length; ++i) {
            aggregateSecret = addmod(aggregateSecret, secrets[indices[i]], LibSecp256k1.Q());
        }
    }

    /// @notice Bitmap of the live key slots: those whose mirrored public key is not the zero point.
    /// @dev A removed node leaves a hole, so slot `i` of `pubkeys` is live iff `pubkeys[i]` is non-zero.
    function liveBitmap(LibSecp256k1.Point[] memory pubkeys) internal pure returns (uint256 bitmap) {
        for (uint256 slot; slot < pubkeys.length; ++slot) {
            if (pubkeys[slot].x | pubkeys[slot].y != 0) bitmap |= uint256(1) << slot;
        }
    }

    /// @notice Sign with the lowest `signerCount` live slots and package the attestation.
    /// @dev Any quorum of live nodes verifies; there is no committee to derive.
    /// @param signerCount How many nodes sign. May exceed `payload.signaturesRequired` to exercise
    ///        over-signing.
    function buildAttestation(
        uint256[] memory secrets,
        LibSecp256k1.Point[] memory pubkeys,
        IVerifier.AttestationPayload memory payload,
        uint256 signerCount
    ) internal view returns (IVerifier.Attestation memory) {
        uint256[] memory indices = pickSignerIndices(liveBitmap(pubkeys), pubkeys.length, signerCount);

        uint256 signersBitmap;
        for (uint256 i; i < indices.length; ++i) {
            signersBitmap |= uint256(1) << indices[i];
        }
        return buildAttestationWithBitmap(secrets, pubkeys, payload, signersBitmap);
    }

    /// @notice Sign with exactly the slots in `signersBitmap` and package the attestation.
    /// @dev For pinned vectors and for tests that choose the signer set themselves.
    function buildAttestationWithBitmap(
        uint256[] memory secrets,
        LibSecp256k1.Point[] memory pubkeys,
        IVerifier.AttestationPayload memory payload,
        uint256 signersBitmap
    ) internal view returns (IVerifier.Attestation memory) {
        uint256[] memory indices = pickSignerIndices(signersBitmap, pubkeys.length, _popCount(signersBitmap));

        (bytes32 signature, address commitment) =
            sign(sumPubkeys(pubkeys, indices), sumSecrets(secrets, indices), message(payload, signersBitmap), 0);

        return IVerifier.Attestation({
            payload: payload,
            signature: IVerifier.SchnorrSignature({
                signature: signature, commitment: commitment, signersBitmap: signersBitmap
            })
        });
    }

    function _popCount(uint256 x) private pure returns (uint256 n) {
        for (; x != 0; x &= x - 1) {
            ++n;
        }
    }
}
