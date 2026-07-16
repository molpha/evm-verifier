// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IVerifier} from "../../src/interfaces/IVerifier.sol";
import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";
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

    function test_verify_returnsFalseForOutOfRangeSignatureScalar() public {
        _addNodes(verifier, 5);
        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("job"), bytes32("value"), 1_700_000_006);
        schnorr.signature = bytes32(LibSecp256k1.Q());

        assertFalse(verifier.verify(update, schnorr));
    }

    function test_verify_returnsFalseWhenSignedMessageFieldsAreTampered() public {
        _addNodes(verifier, 5);
        verifier.setRedundancyBuffer(5);
        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("job"), bytes32("value"), 1_700_000_007);

        IVerifier.DataUpdate memory tampered = update;
        tampered.jobId = bytes32("other job");
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
            jobId: bytes32("job"),
            registryVersion: 1,
            signaturesRequired: 1,
            value: bytes32("value"),
            canonicalTimestamp: 1
        });
        IVerifier.SchnorrSignature memory schnorr;

        vm.expectRevert(bytes("Invalid registry version"));
        verifier.verify(update, schnorr);
    }

    function test_verify_revertsWhenRegistryHasNoNodes() public {
        IVerifier.DataUpdate memory update = IVerifier.DataUpdate({
            jobId: bytes32("job"),
            registryVersion: 0,
            signaturesRequired: 1,
            value: bytes32("value"),
            canonicalTimestamp: 1
        });
        IVerifier.SchnorrSignature memory schnorr;

        vm.expectRevert(bytes("No nodes"));
        verifier.verify(update, schnorr);
    }

    function test_verify_revertsForZeroSignaturesRequired() public {
        _addNodes(verifier, 1);
        IVerifier.DataUpdate memory update = IVerifier.DataUpdate({
            jobId: bytes32("job"),
            registryVersion: uint32(verifier.getRegistryVersion()),
            signaturesRequired: 0,
            value: bytes32("value"),
            canonicalTimestamp: 1
        });
        IVerifier.SchnorrSignature memory schnorr;

        vm.expectRevert(bytes("Zero signatures required"));
        verifier.verify(update, schnorr);
    }

    function test_verify_revertsForZeroSignersBitmap() public {
        _addNodes(verifier, 3);
        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 2, bytes32("job"), bytes32("value"), 2);
        schnorr.signersBitmap = 0;

        vm.expectRevert(bytes("Zero signers bitmap"));
        verifier.verify(update, schnorr);
    }

    function test_verify_revertsForZeroSignature() public {
        _addNodes(verifier, 3);
        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 2, bytes32("job"), bytes32("value"), 3);
        schnorr.signature = 0;

        vm.expectRevert(bytes("Zero signature"));
        verifier.verify(update, schnorr);
    }

    function test_verify_revertsForZeroCommitment() public {
        _addNodes(verifier, 3);
        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 2, bytes32("job"), bytes32("value"), 4);
        schnorr.commitment = address(0);

        vm.expectRevert(bytes("Zero commitment"));
        verifier.verify(update, schnorr);
    }

    function test_verify_revertsWhenSignerCountIsBelowThreshold() public {
        _addNodes(verifier, 5);
        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("job"), bytes32("value"), 5);
        schnorr.signersBitmap &= schnorr.signersBitmap - 1;

        vm.expectRevert(bytes("Not enough signatures"));
        verifier.verify(update, schnorr);
    }

    function test_verify_revertsWhenThresholdExceedsNodeCount() public {
        _addNodes(verifier, 2);
        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 2, bytes32("job"), bytes32("value"), 6);
        update.signaturesRequired = 3;

        vm.expectRevert(bytes("Not enough signatures"));
        verifier.verify(update, schnorr);
    }

    function test_verify_revertsForSignerOutsideSelectedGroup() public {
        _addNodes(verifier, 6);
        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("job"), bytes32("value"), 7);
        schnorr.signersBitmap |= uint256(1) << 255;

        vm.expectRevert(bytes("Signer not selected"));
        verifier.verify(update, schnorr);
    }

    function testFuzz_verifyAcceptsValidSelectedCoalition(
        bytes32 jobId,
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
            _buildVerifyCall(verifier, threshold, signerCount, jobId, value, canonicalTimestamp);

        assertTrue(verifier.verify(update, schnorr));
    }
}
