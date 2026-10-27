// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Ownable} from "solady/auth/Ownable.sol";
import {SSTORE2} from "solady/utils/SSTORE2.sol";

import {Verifier} from "../../src/Verifier.sol";
import {IVerifier} from "../../src/interfaces/IVerifier.sol";
import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";
import {PubkeyBlobLib} from "../../src/libs/PubkeyBlobLib.sol";
import {VerifierTestBase} from "../shared/VerifierTestBase.sol";

contract VerifierRegistryTest is VerifierTestBase {
    using LibSecp256k1 for LibSecp256k1.Point;
    using PubkeyBlobLib for bytes;

    address[] internal expectedRegistryPointers;
    bytes32[] internal expectedRegistryHashes;

    function test_addNode_registersKeyUpdatesAggregateAndVersionsRegistry() public {
        uint256 secret = _secret(1);
        LibSecp256k1.Point memory pubkey = LibSecp256k1.mulAffine(LibSecp256k1.G(), secret);
        bytes memory compressed = LibSecp256k1.compress(pubkey);
        address node = pubkey.toAddress();
        address initialPointer = verifier.getRegistryPointer();

        vm.expectEmit(true, false, false, false, address(verifier));
        emit IVerifier.LogNodeAdded(node, 0, address(0));
        verifier.addNode(compressed, _proofOfPossession(address(verifier), compressed, secret));

        assertEq(verifier.getTotalNodes(), 1);
        assertEq(verifier.getRegistryVersion(), 1);
        assertFalse(verifier.isLatestVersion(0));
        assertTrue(verifier.isLatestVersion(1));
        assertEq(verifier.getRegistryPointer(0), initialPointer);
        assertTrue(verifier.getRegistryPointer() != initialPointer);
    }

    function test_addNode_revertsForDuplicateNode() public {
        _addNodes(verifier, 1);
        bytes memory compressed = LibSecp256k1.compress(pubkeys[0]);
        IVerifier.SchnorrProof memory proof = _proofOfPossession(address(verifier), compressed, secrets[0]);

        vm.expectRevert(IVerifier.NodeNotEligible.selector);
        verifier.addNode(compressed, proof);
    }

    function test_addNode_revertsForInvalidProofOfPossession() public {
        uint256 secret = _secret(1);
        LibSecp256k1.Point memory pubkey = LibSecp256k1.mulAffine(LibSecp256k1.G(), secret);
        bytes memory compressed = LibSecp256k1.compress(pubkey);
        IVerifier.SchnorrProof memory proof = _proofOfPossession(address(verifier), compressed, secret);
        proof.signature = bytes32(uint256(proof.signature) ^ 1);

        vm.expectRevert(IVerifier.InvalidPoP.selector);
        verifier.addNode(compressed, proof);
    }

    function test_addNode_rejectsProofBoundToDifferentVerifier() public {
        Verifier other = new Verifier(address(this));
        uint256 secret = _secret(1);
        LibSecp256k1.Point memory pubkey = LibSecp256k1.mulAffine(LibSecp256k1.G(), secret);
        bytes memory compressed = LibSecp256k1.compress(pubkey);
        IVerifier.SchnorrProof memory proof = _proofOfPossession(address(verifier), compressed, secret);

        vm.expectRevert(IVerifier.InvalidPoP.selector);
        other.addNode(compressed, proof);
    }

    function test_addNode_revertsForMalformedCompressedKeys() public {
        IVerifier.SchnorrProof memory emptyProof;

        vm.expectRevert(LibSecp256k1.InvalidCompressedPubkeyLength.selector);
        verifier.addNode(hex"02", emptyProof);

        vm.expectRevert(LibSecp256k1.InvalidCompressedPubkeyPrefix.selector);
        verifier.addNode(abi.encodePacked(bytes1(0x04), bytes32(uint256(1))), emptyProof);

        vm.expectRevert(LibSecp256k1.CompressedPubkeyXOutOfRange.selector);
        verifier.addNode(abi.encodePacked(bytes1(0x02), bytes32(LibSecp256k1.fieldP())), emptyProof);

        // x = 5 is in range but 5³ + 7 is a quadratic non-residue mod P, so no curve point
        // carries it. Decompression must reject it rather than return an off-curve point.
        vm.expectRevert(LibSecp256k1.PointNotOnCurve.selector);
        verifier.addNode(abi.encodePacked(bytes1(0x02), bytes32(uint256(5))), emptyProof);
    }

    function test_addNode_revertsForNonAdmin() public {
        uint256 secret = _secret(1);
        LibSecp256k1.Point memory pubkey = LibSecp256k1.mulAffine(LibSecp256k1.G(), secret);
        bytes memory compressed = LibSecp256k1.compress(pubkey);
        IVerifier.SchnorrProof memory proof = _proofOfPossession(address(verifier), compressed, secret);

        vm.prank(makeAddr("caller"));
        vm.expectRevert(Ownable.Unauthorized.selector);
        verifier.addNode(compressed, proof);
    }

    function test_removeNode_resetsAggregateWhenRemovingOnlyNode() public {
        _addNodes(verifier, 1);
        address node = pubkeys[0].toAddress();

        vm.expectEmit(true, false, false, false, address(verifier));
        emit IVerifier.LogNodeRemoved(node, 0, address(0));
        verifier.removeNode(node, 0);

        assertEq(verifier.getTotalNodes(), 0);
    }

    function test_removeNode_leavesAHoleAndMovesNoOtherNode() public {
        _addNodes(verifier, 3);
        address removed = pubkeys[1].toAddress();
        address last = pubkeys[2].toAddress();

        _removeNode(verifier, 1);

        assertEq(verifier.getTotalNodes(), 3, "slot count: the hole is kept");
        assertEq(verifier.nodeStatus(removed), RETIRED, "removed node must be retired");
        assertTrue(verifier.isNode(last), "the last node stays active in its own slot");

        // The blob is [pubkeys[0], hole, pubkeys[2]]: nobody moved.
        LibSecp256k1.Point[] memory expected = new LibSecp256k1.Point[](3);
        expected[0] = pubkeys[0];
        expected[2] = pubkeys[2];
        assertEq(_keysCommitmentAt(verifier), _keysCommitmentOf(expected), "slot 2 keeps its key");
        bytes memory blob = SSTORE2.read(verifier.getRegistryPointer());
        assertEq(blob.getNode(1).x, 0);
        assertEq(blob.getNode(1).y, 0);
    }

    function test_removeNode_removingTheLastTrimsTheSlotCount() public {
        _addNodes(verifier, 3);
        address first = pubkeys[0].toAddress();
        address second = pubkeys[1].toAddress();
        address last = pubkeys[2].toAddress();

        _removeNode(verifier, 2);

        assertEq(verifier.getTotalNodes(), 2, "the trailing slot is trimmed");
        assertEq(verifier.nodeStatus(last), RETIRED, "removed tail node must be retired");
        assertTrue(verifier.isNode(first), "surviving nodes must stay active");
        assertTrue(verifier.isNode(second), "surviving nodes must stay active");

        LibSecp256k1.Point[] memory expected = new LibSecp256k1.Point[](2);
        expected[0] = pubkeys[0];
        expected[1] = pubkeys[1];
        assertEq(_keysCommitmentAt(verifier), _keysCommitmentOf(expected), "keys after tail removal");
    }

    function test_removeNode_trimsEveryTrailingHole() public {
        _addNodes(verifier, 4);
        _removeNode(verifier, 2);
        _removeNode(verifier, 1);
        assertEq(verifier.getTotalNodes(), 4, "holes in the middle are kept");

        _removeNode(verifier, 3);
        assertEq(verifier.getTotalNodes(), 1, "slots 1..3 are all holes behind slot 0");
        LibSecp256k1.Point[] memory expected = new LibSecp256k1.Point[](1);
        expected[0] = pubkeys[0];
        assertEq(_keysCommitmentAt(verifier), _keysCommitmentOf(expected));
    }

    function test_addNode_takesTheLowestHoleAndEmitsItsSlot() public {
        _addNodes(verifier, 5);
        _removeNode(verifier, 3);
        _removeNode(verifier, 1);

        uint256 secret = _secret(500);
        LibSecp256k1.Point memory pubkey = LibSecp256k1.mulAffine(LibSecp256k1.G(), secret);
        bytes memory compressed = LibSecp256k1.compress(pubkey);

        vm.expectEmit(true, false, false, false, address(verifier));
        emit IVerifier.LogNodeAdded(pubkey.toAddress(), 1, address(0));
        verifier.addNode(compressed, _proofOfPossession(address(verifier), compressed, secret));

        assertEq(verifier.getTotalNodes(), 5, "a hole was filled, no slot added");
        bytes memory blob = SSTORE2.read(verifier.getRegistryPointer());
        assertEq(blob.getNode(1).x, pubkey.x);
        assertEq(blob.getNode(0).x, pubkeys[0].x);
        assertEq(blob.getNode(2).x, pubkeys[2].x);
        assertEq(blob.getNode(3).x, 0, "the higher hole is still a hole");
        assertEq(blob.getNode(4).x, pubkeys[4].x);

        // The next one takes slot 3, then the one after appends.
        _appendNode(verifier, 501);
        assertEq(verifier.getTotalNodes(), 5);
        assertEq(SSTORE2.read(verifier.getRegistryPointer()).getNode(3).x, pubkeys[pubkeys.length - 1].x);
        _appendNode(verifier, 502);
        assertEq(verifier.getTotalNodes(), 6, "no hole left: append");
    }

    function test_addNode_intoAHoleKeepsEveryOtherNodeVerifying() public {
        _addNodes(verifier, 6);
        _removeNode(verifier, 2);
        _appendNode(verifier, 600); // takes slot 2

        // A mirrored slot-2 key was replaced; rebuild the mirrors to match the blob.
        secrets[2] = secrets[secrets.length - 1];
        pubkeys[2] = pubkeys[pubkeys.length - 1];
        secrets.pop();
        pubkeys.pop();

        (IVerifier.AttestationPayload memory update, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 6, bytes32("hole"), bytes32("value"));
        assertEq(schnorr.signersBitmap, 0x3f, "slots 0..5 all sign, including the new node in slot 2");
        _assertVerifyOk(verifier, update, schnorr);
    }

    function test_removeNode_rejectsReAddOfRetiredAddress() public {
        _addNodes(verifier, 2);
        address node = pubkeys[0].toAddress();
        bytes memory compressed = LibSecp256k1.compress(pubkeys[0]);
        IVerifier.SchnorrProof memory proof = _proofOfPossession(address(verifier), compressed, secrets[0]);

        verifier.removeNode(node, 0);

        vm.expectRevert(IVerifier.NodeNotEligible.selector);
        verifier.addNode(compressed, proof);
    }

    function test_removeNode_revertsForOutOfBoundsIndex() public {
        _addNodes(verifier, 1);

        vm.expectRevert(IVerifier.IndexWitnessMismatch.selector);
        verifier.removeNode(pubkeys[0].toAddress(), 1);
    }

    /// @dev Signer bitmaps are one 256-bit word, so a 257th slot could never be addressed by a
    ///      signature. The cap is on slots: a hole is a free slot, a full table of live nodes is not.
    function test_addNode_revertsWhenRegistryIsFull() public {
        _addNodes(verifier, 256);
        assertEq(verifier.getTotalNodes(), 256);

        uint256 secret = _secret(1000);
        bytes memory compressed = LibSecp256k1.compress(LibSecp256k1.mulAffine(LibSecp256k1.G(), secret));
        IVerifier.SchnorrProof memory proof = _proofOfPossession(address(verifier), compressed, secret);

        vm.expectRevert(IVerifier.MaxNodesReached.selector);
        verifier.addNode(compressed, proof);

        _removeNode(verifier, 0);
        assertEq(verifier.getTotalNodes(), 256, "a hole in the middle keeps the slot count");
        verifier.addNode(compressed, proof);
        assertEq(verifier.getTotalNodes(), 256, "the hole is reusable");

        _expectFullRegistryRevert(_secret(1001));
    }

    function _expectFullRegistryRevert(uint256 secret) internal {
        bytes memory compressed = LibSecp256k1.compress(LibSecp256k1.mulAffine(LibSecp256k1.G(), secret));
        IVerifier.SchnorrProof memory proof = _proofOfPossession(address(verifier), compressed, secret);
        vm.expectRevert(IVerifier.MaxNodesReached.selector);
        verifier.addNode(compressed, proof);
    }

    /// @dev Retirement is terminal for the admin path: a second removal must not publish another
    ///      version, or the registry would advance on a no-op.
    function test_removeNode_revertsForAlreadyRetiredNode() public {
        _addNodes(verifier, 2);
        address node = pubkeys[0].toAddress();

        verifier.removeNode(node, 0);
        assertEq(verifier.nodeStatus(node), RETIRED);
        uint256 versionAfterRemoval = verifier.getRegistryVersion();

        vm.expectRevert(IVerifier.NodeNotEligible.selector);
        verifier.removeNode(node, 0);
        assertEq(verifier.getRegistryVersion(), versionAfterRemoval, "no version published");
    }

    function test_removeNode_revertsForNeverRegisteredNode() public {
        _addNodes(verifier, 2);

        vm.expectRevert(IVerifier.NodeNotEligible.selector);
        verifier.removeNode(makeAddr("stranger"), 0);
    }

    function test_removeNode_revertsForNonAdmin() public {
        _addNodes(verifier, 1);

        vm.prank(makeAddr("caller"));
        vm.expectRevert(Ownable.Unauthorized.selector);
        verifier.removeNode(pubkeys[0].toAddress(), 0);
    }

    function test_removeNode_revertsWhenNodeDoesNotMatchIndex() public {
        _addNodes(verifier, 2);

        vm.expectRevert(IVerifier.IndexWitnessMismatch.selector);
        verifier.removeNode(pubkeys[1].toAddress(), 0);
    }

    function test_registryPointersRemainImmutableAcrossMutations() public {
        _addNodes(verifier, 2);
        address pointer1 = verifier.getRegistryPointer(0);
        address pointer2 = verifier.getRegistryPointer(1);

        _removeNode(verifier, 0);

        assertEq(verifier.getRegistryVersion(), 3);
        assertEq(verifier.getRegistryPointer(0), pointer1);
        assertEq(verifier.getRegistryPointer(1), pointer2);
        assertTrue(verifier.getRegistryPointer(2) != pointer2);
    }

    function test_getRegistryPointer_revertsForUnknownVersion() public {
        vm.expectRevert();
        verifier.getRegistryPointer(1);
    }

    function test_isLatestVersion_revertsForUnknownVersion() public {
        vm.expectRevert(IVerifier.InvalidRegistryVersion.selector);
        verifier.isLatestVersion(1);
    }

    function test_isLatestVersion_tracksExactlyOneHeadAcrossMutations() public {
        assertTrue(verifier.isLatestVersion(0));

        _addNodes(verifier, 2);
        assertFalse(verifier.isLatestVersion(0));
        assertFalse(verifier.isLatestVersion(1));
        assertTrue(verifier.isLatestVersion(2));

        _removeNode(verifier, 0);
        assertFalse(verifier.isLatestVersion(2));
        assertTrue(verifier.isLatestVersion(3));

        _appendNode(verifier, 9);
        assertFalse(verifier.isLatestVersion(3));
        assertTrue(verifier.isLatestVersion(4));
    }

    function test_keysCommitment_isStableUntilRegistryChanges() public {
        _addNodes(verifier, 1);
        bytes32 oneNodeHash = _keysCommitmentAt(verifier);
        assertEq(_keysCommitmentAt(verifier), oneNodeHash);
        assertEq(_keysCommitmentAt(verifier, verifier.getRegistryVersion()), oneNodeHash);
    }

    function testFuzz_registryLifecycleInvariants_randomAddRemoveSequences(uint256 seed) public {
        delete secrets;
        delete pubkeys;
        delete slotKey;
        delete expectedRegistryPointers;
        delete expectedRegistryHashes;

        Verifier target = new Verifier(address(this));
        _recordRegistryPointer(target);
        _assertRegistryLifecycleInvariants(target);

        uint256 nextSlot = 1;
        for (uint256 step; step < 64; ++step) {
            uint256 live = _liveCount();
            bool shouldAdd = live == 0 || (live < 16 && uint256(keccak256(abi.encodePacked(seed, step, "op"))) & 1 == 0);

            if (shouldAdd) {
                _appendNode(target, nextSlot++);
                _mirrorAdd(pubkeys.length);
            } else {
                // Remove the n-th live node, wherever it sits.
                uint256 pick = uint256(keccak256(abi.encodePacked(seed, step, "remove"))) % live;
                uint256 slot = _nthLiveSlot(pick);
                _removeNode(target, slot);
                _mirrorRemove(slot);
            }

            _recordRegistryPointer(target);
            _assertRegistryLifecycleInvariants(target);
        }
    }

    /// @dev `slotKey[i]` is 1 + the `pubkeys` index of the node in slot `i`, or 0 for a hole.
    uint256[] internal slotKey;

    /// @dev Mirrors the verifier: the lowest hole, else a new slot.
    function _mirrorAdd(uint256 pubkeyCount) internal {
        for (uint256 i; i < slotKey.length; ++i) {
            if (slotKey[i] == 0) {
                slotKey[i] = pubkeyCount;
                return;
            }
        }
        slotKey.push(pubkeyCount);
    }

    /// @dev Mirrors the verifier: the slot becomes a hole, then trailing holes are dropped.
    function _mirrorRemove(uint256 slot) internal {
        slotKey[slot] = 0;
        while (slotKey.length != 0 && slotKey[slotKey.length - 1] == 0) {
            slotKey.pop();
        }
    }

    function _liveCount() internal view returns (uint256 n) {
        for (uint256 i; i < slotKey.length; ++i) {
            if (slotKey[i] != 0) ++n;
        }
    }

    function _nthLiveSlot(uint256 n) internal view returns (uint256) {
        for (uint256 i; i < slotKey.length; ++i) {
            if (slotKey[i] == 0) continue;
            if (n == 0) return i;
            --n;
        }
        revert("no such live slot");
    }

    /// @dev Removing the node in slot 255 of a full table trims it; a middle removal leaves a hole
    ///      and nobody moves, whatever the table size.
    function test_removeNode_atFullSizeLeavesAHoleInTheMiddleAndTrimsTheLast() public {
        _addNodes(verifier, 256);
        address removed = pubkeys[0].toAddress();
        address last = pubkeys[255].toAddress();

        _removeNode(verifier, 0);

        assertEq(verifier.nodeStatus(removed), RETIRED);
        assertTrue(verifier.isNode(last), "the node in slot 255 stays in slot 255");
        assertEq(verifier.getTotalNodes(), 256);
        assertEq(SSTORE2.read(verifier.getRegistryPointer()).getNode(255).x, pubkeys[255].x);

        _removeNode(verifier, 255);
        assertEq(verifier.getTotalNodes(), 255, "slot 255 is trimmed; the hole at 0 stays");
    }

    function _recordRegistryPointer(Verifier target) internal {
        address pointer = target.getRegistryPointer();
        expectedRegistryPointers.push(pointer);
        expectedRegistryHashes.push(keccak256(SSTORE2.read(pointer)));
    }

    function _assertRegistryLifecycleInvariants(Verifier target) internal view {
        uint256 currentVersion = target.getRegistryVersion();
        assertEq(currentVersion + 1, expectedRegistryPointers.length, "tracked pointer count");

        for (uint256 version; version < expectedRegistryPointers.length; ++version) {
            address pointer = target.getRegistryPointer(version);
            assertEq(pointer, expectedRegistryPointers[version], "historical pointer");
            assertEq(keccak256(SSTORE2.read(pointer)), expectedRegistryHashes[version], "historical blob hash");
            assertEq(target.isLatestVersion(version), version == currentVersion, "latest flag");
        }

        bytes memory blob = SSTORE2.read(target.getRegistryPointer());
        assertEq(target.getTotalNodes(), slotKey.length, "slot count");
        assertEq(blob.getNodesLength(), slotKey.length, "blob length");

        // Every live node sits in its slot with its own key; every hole is the zero point; the last
        // slot is live. The commitment equals an independent hash of the mirrored points.
        LibSecp256k1.Point[] memory expectedPoints = new LibSecp256k1.Point[](slotKey.length);
        for (uint256 i; i < slotKey.length; ++i) {
            LibSecp256k1.Point memory stored = blob.getNode(i);
            if (slotKey[i] == 0) {
                assertEq(stored.x | stored.y, 0, "hole is the zero point");
                continue;
            }
            LibSecp256k1.Point memory expected = pubkeys[slotKey[i] - 1];
            expectedPoints[i] = expected;
            assertEq(stored.x, expected.x, "blob node x");
            assertEq(stored.y, expected.y, "blob node y");
            assertEq(target.nodeStatus(stored.toAddress()), ACTIVE, "active node status");
        }
        assertEq(_keysCommitmentAt(target), _keysCommitmentOf(expectedPoints), "commitment over mirrored slots");
    }
}
