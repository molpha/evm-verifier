// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {VerifierTestBase} from "../shared/VerifierTestBase.sol";
import {IVerifier} from "../../src/interfaces/IVerifier.sol";
import {VerifyCodes} from "../../src/libs/VerifyCodes.sol";
import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";
import {LibSchnorrTestSign} from "../libs/LibSchnorrTestSign.sol";

/// @dev Audit probe: mid-loop cancellation. Nodes P, -P, X registered; coalition {P, -P, X}.
///      Checks whether the verify loop's post-loop az==0 check catches an intermediate
///      point-at-infinity (z should be absorbing at 0), or whether a garbage off-curve
///      aggregate can reach verifySignatureTrusted.
contract AuditProbeTest is VerifierTestBase {
    function test_probe_midLoopCancellationRevertsOrVerifiesUnderX() public {
        // Node 1: P
        uint256 secret = _secret(1);
        LibSecp256k1.Point memory pubkey = LibSecp256k1.mulAffine(LibSecp256k1.G(), secret);
        bytes memory compressed = LibSecp256k1.compress(pubkey);
        verifier.addNode(compressed, _proofOfPossession(address(verifier), compressed, secret));

        // Node 2: -P (same x, negated y) — registrable because address differs and PoP is signable.
        uint256 negSecret = LibSecp256k1.Q() - secret;
        LibSecp256k1.Point memory negPubkey = LibSecp256k1.Point({x: pubkey.x, y: LibSecp256k1.fieldP() - pubkey.y});
        bytes memory negCompressed = LibSecp256k1.compress(negPubkey);
        verifier.addNode(negCompressed, _proofOfPossession(address(verifier), negCompressed, negSecret));

        // Node 3: X
        uint256 xSecret = _secret(3);
        LibSecp256k1.Point memory xPubkey = LibSecp256k1.mulAffine(LibSecp256k1.G(), xSecret);
        bytes memory xCompressed = LibSecp256k1.compress(xPubkey);
        verifier.addNode(xCompressed, _proofOfPossession(address(verifier), xCompressed, xSecret));

        verifier.setRedundancyBuffer(0);
        bytes32 sourceId = bytes32("midloop-infinity");
        IVerifier.DataUpdate memory update = IVerifier.DataUpdate({
            sourceId: sourceId,
            registryVersion: uint32(verifier.getRegistryVersion()),
            signaturesRequired: 3,
            value: bytes32("value"),
            canonicalTimestamp: 1_700_000_042
        });

        // True sum P + (-P) + X = X; sign under X alone with combined secret = xSecret.
        uint256 combinedSecret = addmod(addmod(secret, negSecret, LibSecp256k1.Q()), xSecret, LibSecp256k1.Q());
        (bytes32 sig, address commitment) = LibSchnorrTestSign.sign(xPubkey, combinedSecret, _message(update, 7), 0);
        IVerifier.SchnorrSignature memory schnorr =
            IVerifier.SchnorrSignature({signature: sig, commitment: commitment, signersBitmap: 7});

        (bool ok, uint8 code) = verifier.verify(update, schnorr, 0);
        assertFalse(ok);
        assertEq(code, VerifyCodes.R_BAD_AGGREGATE);
    }
}
