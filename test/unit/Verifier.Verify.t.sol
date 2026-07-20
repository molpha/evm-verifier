// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IVerifier} from "../../src/interfaces/IVerifier.sol";
import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";
import {LibSchnorrTestSign} from "../libs/LibSchnorrTestSign.sol";
import {VerifierTestBase} from "../shared/VerifierTestBase.sol";

contract VerifierVerifyTest is VerifierTestBase {
    using LibSecp256k1 for LibSecp256k1.Point;

    function test_verify_acceptsThresholdSignature() public {
        _addNodes(verifier, 5);
        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("job"), bytes32("value"), 1_700_000_000);

        assertTrue(verifier.verify(update, schnorr));
    }

    function test_verify_acceptsMoreSignersThanThreshold() public {
        _addNodes(verifier, 5);
        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, 5, bytes32("job"), bytes32("value"), 1_700_000_001);

        assertTrue(verifier.verify(update, schnorr));
    }

    function test_verify_acceptsHistoricalRegistryVersionAfterNodeSetChanges() public {
        _addNodes(verifier, 4);
        (IVerifier.DataUpdate memory historicalUpdate, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 2, bytes32("historical"), bytes32("value"), 1_700_000_002);
        uint256 historicalVersion = verifier.getRegistryVersion();

        _appendNode(verifier, 5);
        verifier.removeNode(pubkeys[0].toAddress());

        assertTrue(verifier.getRegistryVersion() > historicalVersion);
        assertEq(historicalUpdate.registryVersion, historicalVersion);
        assertTrue(verifier.verify(historicalUpdate, schnorr));
    }

    function test_verify_respectsZeroRedundancyBuffer() public {
        _addNodes(verifier, 5);
        verifier.setRedundancyBuffer(0);
        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("no buffer"), bytes32("value"), 1_700_000_003);

        assertTrue(verifier.verify(update, schnorr));
    }

    function test_verify_capsSelectionGroupAtNodeCount() public {
        _addNodes(verifier, 2);
        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 2, bytes32("capped"), bytes32("value"), 1_700_000_004);

        assertEq(schnorr.signersBitmap, 3);
        assertTrue(verifier.verify(update, schnorr));
    }

    function test_verify_returnsFalseForTamperedSignature() public {
        _addNodes(verifier, 5);
        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("job"), bytes32("value"), 1_700_000_005);
        schnorr.signature = bytes32(uint256(schnorr.signature) ^ 1);

        assertFalse(verifier.verify(update, schnorr));
    }

    function test_verify_revertsForOutOfRangeSignatureScalar() public {
        _addNodes(verifier, 5);
        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("job"), bytes32("value"), 1_700_000_006);
        schnorr.signature = bytes32(LibSecp256k1.Q());

        vm.expectRevert(IVerifier.InvalidSignatureScalar.selector);
        verifier.verify(update, schnorr);
    }

    function test_verify_revertsForNonCanonicalSignatureScalarSPlusQ() public {
        _addNodes(verifier, 5);
        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("job"), bytes32("value"), 1_700_000_006);
        schnorr.signature = bytes32(uint256(1) + LibSecp256k1.Q());

        vm.expectRevert(IVerifier.InvalidSignatureScalar.selector);
        verifier.verify(update, schnorr);
    }

    function test_verify_returnsFalseWhenSignedMessageFieldsAreTampered() public {
        _addNodes(verifier, 5);
        verifier.setRedundancyBuffer(5);
        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("job"), bytes32("value"), 1_700_000_007);

        IVerifier.DataUpdate memory tampered = update;
        tampered.feedId = bytes32("other job");
        assertFalse(verifier.verify(tampered, schnorr));

        tampered = update;
        tampered.value = bytes32("other value");
        assertFalse(verifier.verify(tampered, schnorr));

        tampered = update;
        tampered.canonicalTimestamp += 1;
        assertFalse(verifier.verify(tampered, schnorr));

        tampered = update;
        tampered.signaturesRequired -= 1;
        assertFalse(verifier.verify(tampered, schnorr));
    }

    function test_verify_returnsFalseForTamperedSignerBitmapWithinSelection() public {
        _addNodes(verifier, 5);
        verifier.setRedundancyBuffer(5);
        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("job"), bytes32("value"), 1_700_000_008);

        uint256 removedBit = schnorr.signersBitmap & (~schnorr.signersBitmap + 1);
        uint256 addedBit;
        for (uint256 position; position < 5; ++position) {
            uint256 candidate = uint256(1) << position;
            if (schnorr.signersBitmap & candidate == 0) {
                addedBit = candidate;
                break;
            }
        }
        schnorr.signersBitmap = (schnorr.signersBitmap ^ removedBit) | addedBit;

        assertFalse(verifier.verify(update, schnorr));
    }

    function test_verify_revertsForInvalidRegistryVersion() public {
        IVerifier.DataUpdate memory update = IVerifier.DataUpdate({
            feedId: bytes32("job"),
            registryVersion: 1,
            signaturesRequired: 1,
            value: bytes32("value"),
            canonicalTimestamp: 1
        });
        IVerifier.SchnorrSignature memory schnorr;

        vm.expectRevert(IVerifier.InvalidRegistryVersion.selector);
        verifier.verify(update, schnorr);
    }

    function test_verify_revertsWhenRegistryHasNoNodes() public {
        IVerifier.DataUpdate memory update = IVerifier.DataUpdate({
            feedId: bytes32("job"),
            registryVersion: 0,
            signaturesRequired: 1,
            value: bytes32("value"),
            canonicalTimestamp: 1
        });
        IVerifier.SchnorrSignature memory schnorr;

        vm.expectRevert(IVerifier.NoNodes.selector);
        verifier.verify(update, schnorr);
    }

    function test_verify_revertsForZeroSignaturesRequired() public {
        _addNodes(verifier, 1);
        IVerifier.DataUpdate memory update = IVerifier.DataUpdate({
            feedId: bytes32("job"),
            registryVersion: uint32(verifier.getRegistryVersion()),
            signaturesRequired: 0,
            value: bytes32("value"),
            canonicalTimestamp: 1
        });
        IVerifier.SchnorrSignature memory schnorr;

        vm.expectRevert(IVerifier.ZeroSignaturesRequired.selector);
        verifier.verify(update, schnorr);
    }

    function test_verify_revertsForZeroSignersBitmap() public {
        _addNodes(verifier, 3);
        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 2, bytes32("job"), bytes32("value"), 2);
        schnorr.signersBitmap = 0;

        vm.expectRevert(IVerifier.ZeroSignersBitmap.selector);
        verifier.verify(update, schnorr);
    }

    function test_verify_revertsForZeroSignature() public {
        _addNodes(verifier, 3);
        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 2, bytes32("job"), bytes32("value"), 3);
        schnorr.signature = 0;

        vm.expectRevert(IVerifier.ZeroSignature.selector);
        verifier.verify(update, schnorr);
    }

    function test_verify_revertsForZeroCommitment() public {
        _addNodes(verifier, 3);
        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 2, bytes32("job"), bytes32("value"), 4);
        schnorr.commitment = address(0);

        vm.expectRevert(IVerifier.ZeroCommitment.selector);
        verifier.verify(update, schnorr);
    }

    function test_verify_revertsWhenSignerCountIsBelowThreshold() public {
        _addNodes(verifier, 5);
        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("job"), bytes32("value"), 5);
        schnorr.signersBitmap &= schnorr.signersBitmap - 1;

        vm.expectRevert(IVerifier.NotEnoughSignatures.selector);
        verifier.verify(update, schnorr);
    }

    function test_verify_revertsWhenThresholdExceedsNodeCount() public {
        _addNodes(verifier, 2);
        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 2, bytes32("job"), bytes32("value"), 6);
        update.signaturesRequired = 3;

        vm.expectRevert(IVerifier.NotEnoughSignatures.selector);
        verifier.verify(update, schnorr);
    }

    function test_verify_revertsForSignerOutsideSelectedGroup() public {
        _addNodes(verifier, 6);
        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("job"), bytes32("value"), 7);
        schnorr.signersBitmap |= uint256(1) << 255;

        vm.expectRevert(IVerifier.SignerNotSelected.selector);
        verifier.verify(update, schnorr);
    }

    function test_verify_revertsPredictablyWhenSelectedCoalitionAggregatesToInfinity() public {
        uint256 secret = _secret(1);
        LibSecp256k1.Point memory pubkey = LibSecp256k1.mulAffine(LibSecp256k1.G(), secret);
        bytes memory compressed = LibSecp256k1.compress(pubkey);
        verifier.addNode(compressed, _proofOfPossession(address(verifier), compressed, secret));

        uint256 negatedSecret = LibSecp256k1.Q() - secret;
        LibSecp256k1.Point memory negatedPubkey = LibSecp256k1.Point({x: pubkey.x, y: LibSecp256k1.fieldP() - pubkey.y});
        bytes memory negatedCompressed = LibSecp256k1.compress(negatedPubkey);
        verifier.addNode(negatedCompressed, _proofOfPossession(address(verifier), negatedCompressed, negatedSecret));

        verifier.setRedundancyBuffer(0);
        IVerifier.DataUpdate memory update = IVerifier.DataUpdate({
            feedId: bytes32("infinity"),
            registryVersion: uint32(verifier.getRegistryVersion()),
            signaturesRequired: 2,
            value: bytes32("value"),
            canonicalTimestamp: 1_700_000_009
        });
        IVerifier.SchnorrSignature memory schnorr =
            IVerifier.SchnorrSignature({signature: bytes32(uint256(1)), commitment: address(1), signersBitmap: 3});

        (uint256 aggregateX, uint256 aggregateY) = verifier.getAggregateKey();
        assertEq(aggregateX, 0);
        assertEq(aggregateY, 0);

        vm.expectRevert(IVerifier.InvalidAggregatePublicKey.selector);
        verifier.verify(update, schnorr);
    }

    function test_verify_bitmapBoundaries_nodesOneAnd256AndFullUint256Bitmap() public {
        _addNodes(verifier, 256);

        verifier.setRedundancyBuffer(255);
        IVerifier.DataUpdate memory edgeUpdate = IVerifier.DataUpdate({
            feedId: bytes32("bitmap edge"),
            registryVersion: uint32(verifier.getRegistryVersion()),
            signaturesRequired: 1,
            value: bytes32("edge value"),
            canonicalTimestamp: 1_700_000_010
        });

        uint256 edgeBitmap = uint256(1) | (uint256(1) << 255);
        (uint256 x, uint256 y, uint256 z) =
            LibSecp256k1.addAffinePointToXYZ(pubkeys[0].x, pubkeys[0].y, 1, pubkeys[255].x, pubkeys[255].y);
        LibSecp256k1.Point memory edgeAggregate = LibSecp256k1.toAffineModexpXYZ(x, y, z);
        uint256 edgeSecret = addmod(secrets[0], secrets[255], LibSecp256k1.Q());
        (bytes32 edgeSignature, address edgeCommitment) =
            LibSchnorrTestSign.sign(edgeAggregate, edgeSecret, _message(edgeUpdate, edgeBitmap), 0);
        IVerifier.SchnorrSignature memory edgeSchnorr = IVerifier.SchnorrSignature({
            signature: edgeSignature, commitment: edgeCommitment, signersBitmap: edgeBitmap
        });

        assertTrue(verifier.verify(edgeUpdate, edgeSchnorr), "nodes 1 and 256");

        verifier.setRedundancyBuffer(0);
        IVerifier.DataUpdate memory fullUpdate = IVerifier.DataUpdate({
            feedId: bytes32("bitmap full"),
            registryVersion: uint32(verifier.getRegistryVersion()),
            signaturesRequired: 256,
            value: bytes32("full value"),
            canonicalTimestamp: 1_700_000_011
        });

        uint256 fullSecret;
        for (uint256 i; i < secrets.length; ++i) {
            fullSecret = addmod(fullSecret, secrets[i], LibSecp256k1.Q());
        }
        (uint256 fullX, uint256 fullY) = verifier.getAggregateKey();
        LibSecp256k1.Point memory fullAggregate = LibSecp256k1.Point({x: fullX, y: fullY});
        (bytes32 fullSignature, address fullCommitment) =
            LibSchnorrTestSign.sign(fullAggregate, fullSecret, _message(fullUpdate, type(uint256).max), 0);
        IVerifier.SchnorrSignature memory fullSchnorr = IVerifier.SchnorrSignature({
            signature: fullSignature, commitment: fullCommitment, signersBitmap: type(uint256).max
        });

        assertTrue(verifier.verify(fullUpdate, fullSchnorr), "full uint256 bitmap");
    }

    function testFuzz_verifyAcceptsValidSelectedCoalition(
        bytes32 feedId,
        bytes32 value,
        uint64 canonicalTimestamp,
        uint8 thresholdSeed,
        uint8 bufferSeed,
        uint8 signerCountSeed
    ) public {
        _addNodes(verifier, 8);
        uint256 threshold = bound(thresholdSeed, 1, 8);
        uint256 buffer = bound(bufferSeed, 0, 8);
        verifier.setRedundancyBuffer(buffer);
        uint256 groupSize = threshold + buffer;
        if (groupSize > 8) groupSize = 8;
        uint256 signerCount = bound(signerCountSeed, threshold, groupSize);

        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, threshold, signerCount, feedId, value, canonicalTimestamp);

        assertTrue(verifier.verify(update, schnorr));
    }
}
