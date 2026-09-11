// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IVerifier} from "../../src/interfaces/IVerifier.sol";
import {VerifyCodes} from "../../src/libs/VerifyCodes.sol";
import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";
import {MolphaSigLib} from "../../src/test-utils/MolphaSigLib.sol";
import {VerifierTestBase} from "../shared/VerifierTestBase.sol";

contract VerifierVerifyTest is VerifierTestBase {
    using LibSecp256k1 for LibSecp256k1.Point;

    function test_verify_acceptsThresholdSignature() public {
        _addNodes(verifier, 5);
        (IVerifier.AttestationPayload memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("job"), bytes32("value"), 1_700_000_000);

        _assertVerifyOk(verifier, update, schnorr);
    }

    function test_verify_acceptsMoreSignersThanThreshold() public {
        _addNodes(verifier, 5);
        (IVerifier.AttestationPayload memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, 5, bytes32("job"), bytes32("value"), 1_700_000_001);

        _assertVerifyOk(verifier, update, schnorr);
    }

    function test_verify_acceptsHistoricalRegistryVersionAfterNodeSetChanges() public {
        _addNodes(verifier, 4);
        // Sign inside the grace window relative to the upcoming retirement timestamp.
        (IVerifier.AttestationPayload memory historicalUpdate, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 2, bytes32("historical"), bytes32("value"), uint64(block.timestamp + 30));
        uint256 historicalVersion = verifier.getRegistryVersion();

        _appendNode(verifier, 5);
        _removeNode(verifier, 0);

        assertTrue(verifier.getRegistryVersion() > historicalVersion);
        assertEq(historicalUpdate.registryVersion, historicalVersion);
        _assertVerifyOk(verifier, historicalUpdate, schnorr);
    }

    function test_verify_respectsZeroRedundancyBuffer() public {
        _addNodes(verifier, 5);
        verifier.setRedundancyBuffer(0);
        (IVerifier.AttestationPayload memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("no buffer"), bytes32("value"), 1_700_000_003);

        _assertVerifyOk(verifier, update, schnorr);
    }

    function test_verify_capsSelectionGroupAtNodeCount() public {
        _addNodes(verifier, 2);
        (IVerifier.AttestationPayload memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 2, bytes32("capped"), bytes32("value"), 1_700_000_004);

        assertEq(schnorr.signersBitmap, 3);
        _assertVerifyOk(verifier, update, schnorr);
    }

    function test_verify_returnsFalseForTamperedSignature() public {
        _addNodes(verifier, 5);
        (IVerifier.AttestationPayload memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("job"), bytes32("value"), 1_700_000_005);
        schnorr.signature = bytes32(uint256(schnorr.signature) ^ 1);

        _assertVerifyFails(verifier, update, schnorr);
    }

    function test_verify_returnsFalseForOutOfRangeSignatureScalar() public {
        _addNodes(verifier, 5);
        (IVerifier.AttestationPayload memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("job"), bytes32("value"), 1_700_000_006);
        schnorr.signature = bytes32(LibSecp256k1.Q());

        _assertVerifyFails(verifier, update, schnorr);
    }

    function test_verify_returnsFalseForNonCanonicalSignatureScalarSPlusQ() public {
        _addNodes(verifier, 5);
        (IVerifier.AttestationPayload memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("job"), bytes32("value"), 1_700_000_006);
        schnorr.signature = bytes32(uint256(1) + LibSecp256k1.Q());

        _assertVerifyFails(verifier, update, schnorr);
    }

    function test_verify_returnsFalseWhenSignedMessageFieldsAreTampered() public {
        _addNodes(verifier, 5);
        verifier.setRedundancyBuffer(5);
        (IVerifier.AttestationPayload memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("job"), bytes32("value"), 1_700_000_007);

        bytes32 originalSourceId = update.sourceId;

        IVerifier.AttestationPayload memory tamperedSourceId = update;
        tamperedSourceId.sourceId = bytes32("other source");
        _assertVerifyFails(verifier, tamperedSourceId, schnorr, VerifyCodes.R_BAD_SIGNATURE);

        IVerifier.AttestationPayload memory tamperedValue = update;
        tamperedValue.sourceId = originalSourceId;
        tamperedValue.value = bytes32("other value");
        _assertVerifyFails(verifier, tamperedValue, schnorr, VerifyCodes.R_BAD_SIGNATURE);

        IVerifier.AttestationPayload memory tamperedTimestamp = update;
        tamperedTimestamp.sourceId = originalSourceId;
        tamperedTimestamp.canonicalTimestamp += 1;
        _assertVerifyFails(verifier, tamperedTimestamp, schnorr, VerifyCodes.R_BAD_SIGNATURE);

        IVerifier.AttestationPayload memory tamperedThreshold = update;
        tamperedThreshold.sourceId = originalSourceId;
        tamperedThreshold.signaturesRequired -= 1;
        _assertVerifyFails(verifier, tamperedThreshold, schnorr, VerifyCodes.R_BAD_SIGNATURE);
    }

    function test_verify_returnsFalseForTamperedSignerBitmapWithinSelection() public {
        _addNodes(verifier, 5);
        verifier.setRedundancyBuffer(5);
        (IVerifier.AttestationPayload memory update, IVerifier.SchnorrSignature memory schnorr) =
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

        _assertVerifyFails(verifier, update, schnorr);
    }

    function test_verify_returnsFalseForInvalidRegistryVersion() public {
        bytes32 sourceId = bytes32("job");
        IVerifier.AttestationPayload memory update = IVerifier.AttestationPayload({
            sourceId: sourceId,
            registryVersion: 1,
            signaturesRequired: 1,
            value: bytes32("value"),
            canonicalTimestamp: 1
        });
        IVerifier.SchnorrSignature memory schnorr;

        _assertVerifyFails(verifier, update, schnorr, VerifyCodes.R_MALFORMED);
    }

    function test_verify_returnsFalseWhenRegistryHasNoNodes() public {
        bytes32 sourceId = bytes32("job");
        IVerifier.AttestationPayload memory update = IVerifier.AttestationPayload({
            sourceId: sourceId,
            registryVersion: 0,
            signaturesRequired: 1,
            value: bytes32("value"),
            canonicalTimestamp: 1
        });
        IVerifier.SchnorrSignature memory schnorr =
            IVerifier.SchnorrSignature({signature: bytes32(uint256(1)), commitment: address(1), signersBitmap: 1});

        _assertVerifyFails(verifier, update, schnorr, VerifyCodes.R_BAD_QUORUM);
    }

    function test_verify_returnsFalseForZeroSignaturesRequired() public {
        _addNodes(verifier, 1);
        bytes32 sourceId = bytes32("job");
        IVerifier.AttestationPayload memory update = IVerifier.AttestationPayload({
            sourceId: sourceId,
            registryVersion: uint32(verifier.getRegistryVersion()),
            signaturesRequired: 0,
            value: bytes32("value"),
            canonicalTimestamp: 1
        });
        IVerifier.SchnorrSignature memory schnorr;

        _assertVerifyFails(verifier, update, schnorr);
    }

    function test_verify_returnsFalseForZeroSignersBitmap() public {
        _addNodes(verifier, 3);
        (IVerifier.AttestationPayload memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 2, bytes32("job"), bytes32("value"), uint64(block.timestamp));
        schnorr.signersBitmap = 0;

        _assertVerifyFails(verifier, update, schnorr);
    }

    function test_verify_returnsFalseForZeroSignature() public {
        _addNodes(verifier, 3);
        (IVerifier.AttestationPayload memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 2, bytes32("job"), bytes32("value"), uint64(block.timestamp));
        schnorr.signature = 0;

        _assertVerifyFails(verifier, update, schnorr);
    }

    function test_verify_returnsFalseForZeroCommitment() public {
        _addNodes(verifier, 3);
        (IVerifier.AttestationPayload memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 2, bytes32("job"), bytes32("value"), uint64(block.timestamp));
        schnorr.commitment = address(0);

        _assertVerifyFails(verifier, update, schnorr);
    }

    function test_verify_returnsFalseWhenSignerCountIsBelowThreshold() public {
        _addNodes(verifier, 5);
        (IVerifier.AttestationPayload memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("job"), bytes32("value"), uint64(block.timestamp));
        schnorr.signersBitmap &= schnorr.signersBitmap - 1;

        _assertVerifyFails(verifier, update, schnorr);
    }

    function test_verify_returnsFalseWhenThresholdExceedsNodeCount() public {
        _addNodes(verifier, 2);
        (IVerifier.AttestationPayload memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 2, bytes32("job"), bytes32("value"), uint64(block.timestamp));
        update.signaturesRequired = 3;

        _assertVerifyFails(verifier, update, schnorr);
    }

    function test_verify_returnsFalseForSignerOutsideSelectedGroup() public {
        _addNodes(verifier, 6);
        (IVerifier.AttestationPayload memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("job"), bytes32("value"), uint64(block.timestamp));
        schnorr.signersBitmap |= uint256(1) << 255;

        _assertVerifyFails(verifier, update, schnorr);
    }

    function test_verify_returnsFalseWhenSelectedCoalitionAggregatesToInfinity() public {
        uint256 secret = _secret(1);
        LibSecp256k1.Point memory pubkey = LibSecp256k1.mulAffine(LibSecp256k1.G(), secret);
        bytes memory compressed = LibSecp256k1.compress(pubkey);
        verifier.addNode(compressed, _proofOfPossession(address(verifier), compressed, secret));

        uint256 negatedSecret = LibSecp256k1.Q() - secret;
        LibSecp256k1.Point memory negatedPubkey = LibSecp256k1.Point({x: pubkey.x, y: LibSecp256k1.fieldP() - pubkey.y});
        bytes memory negatedCompressed = LibSecp256k1.compress(negatedPubkey);
        verifier.addNode(negatedCompressed, _proofOfPossession(address(verifier), negatedCompressed, negatedSecret));

        verifier.setRedundancyBuffer(0);
        bytes32 sourceId = bytes32("infinity");
        IVerifier.AttestationPayload memory update = IVerifier.AttestationPayload({
            sourceId: sourceId,
            registryVersion: uint32(verifier.getRegistryVersion()),
            signaturesRequired: 2,
            value: bytes32("value"),
            canonicalTimestamp: 1_700_000_009
        });
        IVerifier.SchnorrSignature memory schnorr =
            IVerifier.SchnorrSignature({signature: bytes32(uint256(1)), commitment: address(1), signersBitmap: 3});

        _assertVerifyFails(verifier, update, schnorr);
    }

    function test_verify_bitmapBoundaries_nodesOneAnd256AndFullUint256Bitmap() public {
        _addNodes(verifier, 256);

        verifier.setRedundancyBuffer(255);
        bytes32 edgeSourceId = bytes32("bitmap edge");
        IVerifier.AttestationPayload memory edgeUpdate = IVerifier.AttestationPayload({
            sourceId: edgeSourceId,
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
            MolphaSigLib.sign(edgeAggregate, edgeSecret, _message(edgeUpdate, edgeBitmap), 0);
        IVerifier.SchnorrSignature memory edgeSchnorr = IVerifier.SchnorrSignature({
            signature: edgeSignature, commitment: edgeCommitment, signersBitmap: edgeBitmap
        });

        _assertVerifyOk(verifier, edgeUpdate, edgeSchnorr);

        // A u8 threshold tops out at 255. A one-node redundancy buffer expands the selected
        // group to all 256 nodes, so the verifier still exercises a full uint256 bitmap.
        verifier.setRedundancyBuffer(1);
        bytes32 fullSourceId = bytes32("bitmap full");
        IVerifier.AttestationPayload memory fullUpdate = IVerifier.AttestationPayload({
            sourceId: fullSourceId,
            registryVersion: uint32(verifier.getRegistryVersion()),
            signaturesRequired: 255,
            value: bytes32("full value"),
            canonicalTimestamp: 1_700_000_011
        });

        uint256 fullSecret;
        for (uint256 i; i < secrets.length; ++i) {
            fullSecret = addmod(fullSecret, secrets[i], LibSecp256k1.Q());
        }
        uint256[] memory allIndices = new uint256[](256);
        for (uint256 i; i < 256; ++i) {
            allIndices[i] = i;
        }
        LibSecp256k1.Point memory fullAggregate = _sumPubkeys(allIndices);
        (bytes32 fullSignature, address fullCommitment) =
            MolphaSigLib.sign(fullAggregate, fullSecret, _message(fullUpdate, type(uint256).max), 0);
        IVerifier.SchnorrSignature memory fullSchnorr = IVerifier.SchnorrSignature({
            signature: fullSignature, commitment: fullCommitment, signersBitmap: type(uint256).max
        });

        _assertVerifyOk(verifier, fullUpdate, fullSchnorr);
    }

    function test_verify_maxAgeZeroSkipsFreshness() public {
        _addNodes(verifier, 5);
        uint64 ts = 1_700_000_030;
        (IVerifier.AttestationPayload memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("freshness-skip"), bytes32("value"), ts);

        vm.warp(ts + 1_000_000);
        _assertVerifyOk(verifier, update, schnorr, 0);
    }

    function test_verify_acceptsUpdateWithinMaxAge() public {
        _addNodes(verifier, 5);
        uint64 ts = 1_700_000_031;
        (IVerifier.AttestationPayload memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("freshness-ok"), bytes32("value"), ts);

        vm.warp(ts + 100);
        _assertVerifyOk(verifier, update, schnorr, 3600);
    }

    function test_verify_returnsStaleWhenOlderThanMaxAge() public {
        _addNodes(verifier, 5);
        uint64 ts = 1_700_000_032;
        uint64 maxAge = 3600;
        (IVerifier.AttestationPayload memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("freshness-stale"), bytes32("value"), ts);

        vm.warp(ts + maxAge + 1);
        _assertVerifyFails(verifier, update, schnorr, maxAge, VerifyCodes.R_STALE);
    }

    function test_verify_returnsMalformedForFutureTimestamp() public {
        _addNodes(verifier, 5);
        uint64 ts = 1_700_000_033;
        (IVerifier.AttestationPayload memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("freshness-future"), bytes32("value"), ts);

        vm.warp(ts - 1);
        _assertVerifyFails(verifier, update, schnorr, 3600, VerifyCodes.R_MALFORMED);
    }

    function testFuzz_verifyAcceptsValidSelectedCoalition(
        bytes32 sourceId,
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

        // Current version has no upper bound; only require ts >= activatesAt.
        uint64 ts = uint64(bound(canonicalTimestamp, block.timestamp, type(uint64).max));

        (IVerifier.AttestationPayload memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, threshold, signerCount, sourceId, value, ts);

        _assertVerifyOk(verifier, update, schnorr);
    }

    function test_verify_returnsNotYetActiveWhenTimestampBeforeActivatesAt() public {
        _addNodes(verifier, 3);
        uint256 version = verifier.getRegistryVersion();
        uint64 activatesAtTs = uint64(verifier.activatesAt(version));
        assertTrue(activatesAtTs > 0);

        (IVerifier.AttestationPayload memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 2, bytes32("not-yet"), bytes32("value"), activatesAtTs - 1);

        _assertVerifyFails(verifier, update, schnorr, VerifyCodes.R_NOT_YET_ACTIVE);
    }

    function test_verify_acceptsRetiredVersionInsideGraceWindow() public {
        _addNodes(verifier, 4);
        uint64 ts = uint64(block.timestamp + 30);
        (IVerifier.AttestationPayload memory historicalUpdate, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 2, bytes32("grace-ok"), bytes32("value"), ts);
        uint256 historicalVersion = verifier.getRegistryVersion();

        // Same-block retirement: window is [activatesAt, activatesAt + PREVIOUS_GRACE].
        verifier.setRedundancyBuffer(1);
        assertEq(verifier.retiredAt(historicalVersion), block.timestamp);
        assertTrue(ts <= block.timestamp + PREVIOUS_GRACE);

        _assertVerifyOk(verifier, historicalUpdate, schnorr);
    }

    function test_verify_returnsVersionExpiredOutsideGraceWindow() public {
        _addNodes(verifier, 4);
        // Far enough past activation that same-block retirement leaves it outside grace.
        uint64 ts = uint64(block.timestamp + PREVIOUS_GRACE + 1);
        (IVerifier.AttestationPayload memory historicalUpdate, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 2, bytes32("expired"), bytes32("value"), ts);
        uint256 historicalVersion = verifier.getRegistryVersion();

        verifier.setRedundancyBuffer(1);
        assertTrue(ts > verifier.retiredAt(historicalVersion) + PREVIOUS_GRACE);

        _assertVerifyFails(verifier, historicalUpdate, schnorr, VerifyCodes.R_VERSION_EXPIRED);
    }

    function test_verify_currentVersionHasNoUpperBound() public {
        _addNodes(verifier, 3);
        uint64 farFuture = uint64(block.timestamp + 365 days);
        (IVerifier.AttestationPayload memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 2, bytes32("current-unbounded"), bytes32("value"), farFuture);

        _assertVerifyOk(verifier, update, schnorr);
    }
}
