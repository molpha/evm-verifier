// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {SSTORE2} from "solady/utils/SSTORE2.sol";

import {IVerifier} from "../../src/interfaces/IVerifier.sol";
import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";
import {CompromiseLib} from "../../src/libs/CompromiseLib.sol";
import {PubkeyBlobLib} from "../../src/libs/PubkeyBlobLib.sol";
import {VerifyCodes} from "../../src/libs/VerifyCodes.sol";
import {Verifier} from "../../src/Verifier.sol";
import {VerifierTestBase} from "../shared/VerifierTestBase.sol";

contract VerifierCompromiseTest is VerifierTestBase {
    using LibSecp256k1 for LibSecp256k1.Point;
    using PubkeyBlobLib for bytes;

    function test_pubkeyAddressFromScalar_matchesMulAffine() public view {
        uint256 sk = _secret(7);
        address fromScalar = LibSecp256k1.pubkeyAddressFromScalar(sk);
        address fromMul = LibSecp256k1.mulAffine(LibSecp256k1.G(), sk).toAddress();
        assertEq(fromScalar, fromMul);
    }

    function test_flagCompromisedKey_revertsForInvalidScalars() public {
        _addNodes(verifier, 1);
        uint256 version = verifier.getRegistryVersion();

        vm.expectRevert(IVerifier.InvalidPrivateKeyScalar.selector);
        verifier.flagCompromisedKey(0, version, 0, SKIP_CURRENT_INDEX);

        vm.expectRevert(IVerifier.InvalidPrivateKeyScalar.selector);
        verifier.flagCompromisedKey(LibSecp256k1.Q(), version, 0, SKIP_CURRENT_INDEX);
    }

    function test_flagCompromisedKey_revertsOnWitnessMismatch() public {
        _addNodes(verifier, 2);
        uint256 version = verifier.getRegistryVersion();

        // Correct key for node 0, wrong witness index 1.
        vm.expectRevert(IVerifier.WitnessMismatch.selector);
        verifier.flagCompromisedKey(secrets[0], version, 1, SKIP_CURRENT_INDEX);
    }

    /// @dev The flag is only meaningful for keys the registry has actually seen; an arbitrary
    ///      scalar must not create bookkeeping for a node that never existed.
    function test_flagCompromisedKey_revertsForKeyThatWasNeverRegistered() public {
        _addNodes(verifier, 2);
        uint256 version = verifier.getRegistryVersion();
        uint256 strangerSecret = _secret(999);

        vm.expectRevert(IVerifier.NodeNotEligible.selector);
        verifier.flagCompromisedKey(strangerSecret, version, 0, SKIP_CURRENT_INDEX);
    }

    /// @dev The witness index is bounds-checked against the version's node count before the blob is
    ///      read, since an out-of-range read would return zero bytes rather than revert.
    function test_flagCompromisedKey_revertsForWitnessIndexPastNodeCount() public {
        _addNodes(verifier, 2);
        uint256 version = verifier.getRegistryVersion();

        vm.expectRevert(IVerifier.WitnessMismatch.selector);
        verifier.flagCompromisedKey(secrets[0], version, 2, SKIP_CURRENT_INDEX);

        vm.expectRevert(IVerifier.WitnessMismatch.selector);
        verifier.flagCompromisedKey(secrets[0], version, type(uint256).max, SKIP_CURRENT_INDEX);
    }

    function test_flagCompromisedKey_revertsForUnknownWitnessVersion() public {
        _addNodes(verifier, 1);
        uint256 unknownVersion = verifier.getRegistryVersion() + 1;

        vm.expectRevert(IVerifier.InvalidRegistryVersion.selector);
        verifier.flagCompromisedKey(secrets[0], unknownVersion, 0, SKIP_CURRENT_INDEX);
    }

    /// @dev When the witness already is the live version there is nothing left to seed, so the
    ///      supplied `currentIndex` is redundant and must be ignored rather than re-checked.
    function test_flagCompromisedKey_ignoresCurrentIndexWhenWitnessIsTheLiveVersion() public {
        _addNodes(verifier, 3);
        uint256 version = verifier.getRegistryVersion();
        address node = pubkeys[1].toAddress();

        verifier.flagCompromisedKey(secrets[1], version, 1, 1);

        assertEq(verifier.nodeStatus(node), COMPROMISED);

        // Observable through verification: with 3 nodes the whole set is selected, so a 2-of-3
        // coalition drawn from the lowest indices includes the flagged signer at blob index 1.
        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 2, 2, bytes32("live-witness"), bytes32("value"), uint64(block.timestamp));
        assertEq(schnorr.signersBitmap & (uint256(1) << 1), uint256(1) << 1, "flagged signer is in the coalition");
        _assertVerifyFails(verifier, update, schnorr, VerifyCodes.R_COMPROMISED_QUORUM);
    }

    /// @dev A retired node is gone from the live blob, so a stale `currentIndex` would point at the
    ///      node that swapped into its slot. The live-version seeding is skipped on status, which is
    ///      what keeps that stale witness from reverting the whole flag.
    function test_flagCompromisedKey_skipsLiveSeedingForARetiredNode() public {
        _addNodes(verifier, 2);
        uint256 witnessVersion = verifier.getRegistryVersion();
        address node = pubkeys[0].toAddress();

        verifier.removeNode(node, 0);
        assertEq(verifier.nodeStatus(node), RETIRED);
        // Swap-and-pop moved the surviving node into slot 0, so index 0 is now someone else.
        assertEq(SSTORE2.read(verifier.getRegistryPointer()).getNode(0).toAddress(), pubkeys[1].toAddress());

        verifier.flagCompromisedKey(secrets[0], witnessVersion, 0, 0);

        assertEq(verifier.nodeStatus(node), COMPROMISED);
    }

    /// @dev For a still-active node the live-version witness is checked, so a wrong `currentIndex`
    ///      has to fail loudly instead of seeding the wrong bit.
    function test_flagCompromisedKey_revertsForWrongCurrentIndex() public {
        _addNodes(verifier, 3);
        uint256 witnessVersion = verifier.getRegistryVersion();
        verifier.setRedundancyBuffer(3); // advance so current != witness

        vm.expectRevert(IVerifier.WitnessMismatch.selector);
        verifier.flagCompromisedKey(secrets[1], witnessVersion, 1, 2);

        assertEq(verifier.nodeStatus(pubkeys[1].toAddress()), ACTIVE, "status untouched by the failed flag");
    }

    function test_flagCompromisedKey_seedsWitnessAndCurrent() public {
        _addNodes(verifier, 3);
        uint256 historicalVersion = verifier.getRegistryVersion();
        address node = pubkeys[1].toAddress();

        // Advance registry so current != witness.
        verifier.setRedundancyBuffer(3);
        assertTrue(verifier.getRegistryVersion() > historicalVersion);
        assertTrue(verifier.isNode(node));

        vm.expectEmit(true, false, false, true, address(verifier));
        emit IVerifier.KeyCompromised(node, historicalVersion, 1);
        verifier.flagCompromisedKey(secrets[1], historicalVersion, 1, 1);

        assertEq(verifier.nodeStatus(node), COMPROMISED);

        // Both versions seeded; second flag reverts.
        vm.expectRevert(IVerifier.KeyAlreadyCompromised.selector);
        verifier.flagCompromisedKey(secrets[1], historicalVersion, 1, SKIP_CURRENT_INDEX);
    }

    function test_flagCompromisedKey_rejectsReAdd() public {
        _addNodes(verifier, 1);
        address node = pubkeys[0].toAddress();
        uint256 version = verifier.getRegistryVersion();
        verifier.flagCompromisedKey(secrets[0], version, 0, SKIP_CURRENT_INDEX);
        verifier.removeFlagged(0, node);

        bytes memory compressed = LibSecp256k1.compress(pubkeys[0]);
        IVerifier.SchnorrProof memory proof = _proofOfPossession(address(verifier), compressed, secrets[0]);
        vm.expectRevert(IVerifier.NodeNotEligible.selector);
        verifier.addNode(compressed, proof);
    }

    function test_backfillCompromised_seedsHistoricalAndDoubleBackfillReverts() public {
        _addNodes(verifier, 2);
        uint256 v1 = verifier.getRegistryVersion();
        address node = pubkeys[0].toAddress();

        verifier.removeNode(node, 0);
        assertEq(verifier.nodeStatus(node), RETIRED);

        verifier.flagCompromisedKey(secrets[0], v1, 0, SKIP_CURRENT_INDEX);
        assertEq(verifier.nodeStatus(node), COMPROMISED);

        Verifier v = new Verifier(address(this), 2);
        uint256 s0 = _secret(50);
        uint256 s1 = _secret(51);
        LibSecp256k1.Point memory p0 = LibSecp256k1.mulAffine(LibSecp256k1.G(), s0);
        LibSecp256k1.Point memory p1 = LibSecp256k1.mulAffine(LibSecp256k1.G(), s1);
        bytes memory c0 = LibSecp256k1.compress(p0);
        bytes memory c1 = LibSecp256k1.compress(p1);
        v.addNode(c0, _proofOfPossession(address(v), c0, s0)); // version 1
        uint256 ver1 = v.getRegistryVersion();
        v.addNode(c1, _proofOfPossession(address(v), c1, s1)); // version 2
        uint256 ver2 = v.getRegistryVersion();
        address n0 = p0.toAddress();
        v.removeNode(n0, 0); // version 3 — n0 gone from current

        v.flagCompromisedKey(s0, ver2, 0, SKIP_CURRENT_INDEX); // seeds ver2 only

        vm.expectEmit(true, false, false, true, address(v));
        emit IVerifier.CompromiseBackfilled(n0, ver1, 0);
        v.backfillCompromised(n0, ver1, 0);

        vm.expectRevert(IVerifier.AlreadyCounted.selector);
        v.backfillCompromised(n0, ver1, 0);
    }

    function test_removeFlagged_revertsIfNotCompromised() public {
        _addNodes(verifier, 1);
        vm.expectRevert(IVerifier.KeyNotCompromised.selector);
        verifier.removeFlagged(0, pubkeys[0].toAddress());
    }

    function test_removeFlagged_removesAndEmits() public {
        _addNodes(verifier, 2);
        address node = pubkeys[0].toAddress();
        uint256 version = verifier.getRegistryVersion();
        verifier.flagCompromisedKey(secrets[0], version, 0, SKIP_CURRENT_INDEX);

        uint256 before = verifier.getRegistryVersion();
        vm.expectEmit(true, true, false, true, address(verifier));
        emit IVerifier.FlaggedNodeRemoved(before + 1, node);
        verifier.removeFlagged(0, node);

        assertEq(verifier.nodeStatus(node), COMPROMISED);
        assertEq(verifier.getTotalNodes(), 1);
        assertEq(verifier.getRegistryVersion(), before + 1);
    }

    /// @dev Backfill only seeds versions for a key that is already proven leaked; it is not an
    ///      independent way to mark a node compromised.
    function test_backfillCompromised_revertsForNodeThatIsNotFlagged() public {
        _addNodes(verifier, 2);
        uint256 version = verifier.getRegistryVersion();

        vm.expectRevert(IVerifier.KeyNotCompromised.selector);
        verifier.backfillCompromised(pubkeys[0].toAddress(), version, 0);

        verifier.removeNode(pubkeys[1].toAddress(), 1);
        vm.expectRevert(IVerifier.KeyNotCompromised.selector);
        verifier.backfillCompromised(pubkeys[1].toAddress(), version, 1);
    }

    /// @dev The witness is what makes the seeded bit correct: without it the caller could set an
    ///      arbitrary bit in a historical version and discount an honest signer.
    function test_backfillCompromised_revertsOnWitnessMismatch() public {
        _addNodes(verifier, 3);
        uint256 version = verifier.getRegistryVersion();
        address node = pubkeys[0].toAddress();
        verifier.flagCompromisedKey(secrets[0], version, 0, SKIP_CURRENT_INDEX);

        // Right node, wrong slot.
        vm.expectRevert(IVerifier.WitnessMismatch.selector);
        verifier.backfillCompromised(node, version, 1);

        // Right slot, index past the version's node count.
        vm.expectRevert(IVerifier.WitnessMismatch.selector);
        verifier.backfillCompromised(node, version, 3);

        vm.expectRevert(IVerifier.InvalidRegistryVersion.selector);
        verifier.backfillCompromised(node, version + 1, 0);
    }

    /// @dev `removeFlagged` leaves the status terminal, so the node stays eligible to be passed
    ///      again. The second call must fail on the index witness rather than publish an empty
    ///      version off a registry that has nothing left to remove.
    function test_removeFlagged_revertsOnSecondRemovalOfTheSameNode() public {
        _addNodes(verifier, 1);
        address node = pubkeys[0].toAddress();
        verifier.flagCompromisedKey(secrets[0], verifier.getRegistryVersion(), 0, SKIP_CURRENT_INDEX);

        verifier.removeFlagged(0, node);
        assertEq(verifier.getTotalNodes(), 0);
        uint256 versionAfterRemoval = verifier.getRegistryVersion();

        vm.expectRevert(IVerifier.IndexWitnessMismatch.selector);
        verifier.removeFlagged(0, node);
        assertEq(verifier.getRegistryVersion(), versionAfterRemoval, "no version published");
    }

    function test_removeFlagged_revertsWhenIndexDoesNotHoldTheNode() public {
        _addNodes(verifier, 3);
        address node = pubkeys[0].toAddress();
        verifier.flagCompromisedKey(secrets[0], verifier.getRegistryVersion(), 0, SKIP_CURRENT_INDEX);

        vm.expectRevert(IVerifier.IndexWitnessMismatch.selector);
        verifier.removeFlagged(1, node);

        vm.expectRevert(IVerifier.IndexWitnessMismatch.selector);
        verifier.removeFlagged(3, node);
    }

    /// @dev End-to-end check that `permuteOnRemove` is wired into the published version: after the
    ///      flagged node is swapped into a new slot, verification must still discount it at its new
    ///      blob index. A bitmap that failed to follow the swap would silently restore its vote.
    function test_compromiseBitFollowsSwapAndPopIntoTheNextVersion() public {
        _addNodes(verifier, 4);
        address flagged = pubkeys[3].toAddress();
        verifier.flagCompromisedKey(secrets[3], verifier.getRegistryVersion(), 3, SKIP_CURRENT_INDEX);

        // Remove blob index 1; the flagged node at index 3 swaps into slot 1 of the new version.
        _removeNodeMirrored(verifier, 1);
        assertEq(
            SSTORE2.read(verifier.getRegistryPointer()).getNode(1).toAddress(),
            flagged,
            "flagged node moved into slot 1"
        );

        // 3 nodes with buffer 2 means the whole set is selected, so a 2-signer coalition drawn from
        // the lowest indices contains slot 1.
        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 2, 2, bytes32("swap-discount"), bytes32("value"), uint64(block.timestamp));
        assertEq(schnorr.signersBitmap & (uint256(1) << 1), uint256(1) << 1, "flagged slot signed");
        _assertVerifyFails(verifier, update, schnorr, VerifyCodes.R_COMPROMISED_QUORUM);

        // One extra honest signer restores the threshold; the aggregate still covers all three keys,
        // which is what distinguishes discounting from subtracting the key out of the aggregate.
        (update, schnorr) =
            _buildVerifyCall(verifier, 2, 3, bytes32("swap-discount"), bytes32("value"), uint64(block.timestamp));
        _assertVerifyOk(verifier, update, schnorr);
    }

    function test_permuteOnRemove_movesLastBitIntoHole() public pure {
        // Nodes 0..3; compromised bits on index 1 and 3 (last). Remove index 1 → bit 3 moves to 1.
        uint256 bitmap = (uint256(1) << 1) | (uint256(1) << 3);
        uint256 permuted = CompromiseLib.permuteOnRemove(bitmap, 1, 4);
        assertEq(permuted, uint256(1) << 1);
    }

    function test_permuteOnRemove_clearingMiddleDoesNotInheritFlag() public pure {
        // Only middle bit set; remove middle → last bit was clear, result empty.
        uint256 bitmap = uint256(1) << 1;
        uint256 permuted = CompromiseLib.permuteOnRemove(bitmap, 1, 4);
        assertEq(permuted, 0);
    }

    function test_swapAndPop_bitmapTracksMovedNode() public {
        _addNodes(verifier, 4);
        uint256 version = verifier.getRegistryVersion();
        // Flag last node (blob index 3).
        address last = pubkeys[3].toAddress();
        verifier.flagCompromisedKey(secrets[3], version, 3, SKIP_CURRENT_INDEX);

        // Remove middle node (index 1) — last swaps into 1; compromised bit must follow.
        _removeNode(verifier, 1);

        bytes memory blob = SSTORE2.read(verifier.getRegistryPointer());
        assertEq(blob.getNode(1).toAddress(), last);
        assertFalse(verifier.isNode(last));
        assertEq(verifier.nodeStatus(last), COMPROMISED);

        // Forward-prop: add more nodes; flagged node stays in the blob at index 1.
        _appendNode(verifier, 10);
        _appendNode(verifier, 11);
        blob = SSTORE2.read(verifier.getRegistryPointer());
        assertEq(blob.getNode(1).toAddress(), last);
    }

    function test_forwardPropagation_tracksBitAcrossAdds() public {
        _addNodes(verifier, 3);
        uint256 version = verifier.getRegistryVersion();
        address node = pubkeys[0].toAddress();
        verifier.flagCompromisedKey(secrets[0], version, 0, SKIP_CURRENT_INDEX);

        for (uint256 i; i < 5; ++i) {
            _appendNode(verifier, 20 + i);
            bytes memory blob = SSTORE2.read(verifier.getRegistryPointer());
            assertEq(blob.getNode(0).toAddress(), node, "flagged node must stay at index 0");
            assertFalse(verifier.isNode(node));
            assertEq(verifier.nodeStatus(node), COMPROMISED);
        }
    }

    function test_aggregateIntegrity_unrelatedFlagDoesNotBreakValidRound() public {
        _addNodes(verifier, 5);
        (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("agg-ok"), bytes32("value"), uint64(block.timestamp));

        // Flag a non-signer.
        uint256 nonSignerBit = (~schnorr.signersBitmap) & ((uint256(1) << 5) - 1);
        nonSignerBit = nonSignerBit & (~nonSignerBit + 1);
        uint256 blobIndex;
        while ((uint256(1) << blobIndex) != nonSignerBit) {
            unchecked {
                ++blobIndex;
            }
        }
        verifier.flagCompromisedKey(secrets[blobIndex], update.registryVersion, blobIndex, SKIP_CURRENT_INDEX);

        _assertVerifyOk(verifier, update, schnorr);
    }
}
