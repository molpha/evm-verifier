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

    uint256[] internal activePubkeyIndexes;
    address[] internal activeNodes;
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
        Verifier other = new Verifier(address(this), 2);
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

    function test_removeNode_swapsLastNodeIntoRemovedMiddleIndex() public {
        _addNodes(verifier, 3);
        address removed = pubkeys[1].toAddress();
        address swapped = pubkeys[2].toAddress();

        _removeNode(verifier, 1);

        assertEq(verifier.getTotalNodes(), 2);
        assertEq(verifier.nodeStatus(removed), RETIRED, "removed node must be retired");
        assertTrue(verifier.isNode(swapped), "swapped-in node must stay active");

        // The blob must now be exactly [pubkeys[0], pubkeys[2]] in that order.
        LibSecp256k1.Point[] memory expected = new LibSecp256k1.Point[](2);
        expected[0] = pubkeys[0];
        expected[1] = pubkeys[2];
        assertEq(_keysCommitmentAt(verifier), _keysCommitmentOf(expected), "key order after swap-and-pop");
    }

    function test_removeNode_removesLastWithoutReordering() public {
        _addNodes(verifier, 3);
        address first = pubkeys[0].toAddress();
        address second = pubkeys[1].toAddress();
        address last = pubkeys[2].toAddress();

        _removeNode(verifier, 2);

        assertEq(verifier.getTotalNodes(), 2);
        assertEq(verifier.nodeStatus(last), RETIRED, "removed tail node must be retired");
        assertTrue(verifier.isNode(first), "surviving nodes must stay active");
        assertTrue(verifier.isNode(second), "surviving nodes must stay active");

        LibSecp256k1.Point[] memory expected = new LibSecp256k1.Point[](2);
        expected[0] = pubkeys[0];
        expected[1] = pubkeys[1];
        assertEq(_keysCommitmentAt(verifier), _keysCommitmentOf(expected), "key order after tail removal");
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

    /// @dev Signer bitmaps are one 256-bit word, so a 257th node would occupy a slot no signature
    ///      could ever address. The cap counts live nodes, so a removal frees the slot again.
    function test_addNode_revertsWhenRegistryIsFull() public {
        _addNodes(verifier, 256);
        assertEq(verifier.getTotalNodes(), 256);

        uint256 secret = _secret(1000);
        bytes memory compressed = LibSecp256k1.compress(LibSecp256k1.mulAffine(LibSecp256k1.G(), secret));
        IVerifier.SchnorrProof memory proof = _proofOfPossession(address(verifier), compressed, secret);

        vm.expectRevert(IVerifier.MaxNodesReached.selector);
        verifier.addNode(compressed, proof);

        _removeNode(verifier, 0);
        verifier.addNode(compressed, proof);
        assertEq(verifier.getTotalNodes(), 256, "the freed slot is reusable");
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

        verifier.setRedundancyBuffer(5);
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
        delete activePubkeyIndexes;
        delete activeNodes;
        delete expectedRegistryPointers;
        delete expectedRegistryHashes;

        Verifier target = new Verifier(address(this), 2);
        _recordRegistryPointer(target);
        _assertRegistryLifecycleInvariants(target);

        uint256 nextSlot = 1;
        for (uint256 step; step < 64; ++step) {
            bool shouldAdd = activeNodes.length == 0
                || (activeNodes.length < 16 && uint256(keccak256(abi.encodePacked(seed, step, "op"))) & 1 == 0);

            if (shouldAdd) {
                address node = _appendNode(target, nextSlot++);
                activeNodes.push(node);
                activePubkeyIndexes.push(pubkeys.length - 1);
            } else {
                uint256 removeIndex = uint256(keccak256(abi.encodePacked(seed, step, "remove"))) % activeNodes.length;
                _removeNode(target, removeIndex);
                _removeExpectedNode(removeIndex);
            }

            _recordRegistryPointer(target);
            _assertRegistryLifecycleInvariants(target);
        }
    }

    function test_removeNode_swapsNodeFromIndex256IntoRemovedBoundarySlot() public {
        _addNodes(verifier, 256);
        address removed = pubkeys[0].toAddress();
        address swappedFromIndex256 = pubkeys[255].toAddress();

        _removeNode(verifier, 0);

        assertEq(verifier.nodeStatus(removed), RETIRED);
        assertTrue(verifier.isNode(swappedFromIndex256));
    }

    function _recordRegistryPointer(Verifier target) internal {
        address pointer = target.getRegistryPointer();
        expectedRegistryPointers.push(pointer);
        expectedRegistryHashes.push(keccak256(SSTORE2.read(pointer)));
    }

    function _removeExpectedNode(uint256 index) internal {
        uint256 last = activeNodes.length - 1;
        if (index != last) {
            activeNodes[index] = activeNodes[last];
            activePubkeyIndexes[index] = activePubkeyIndexes[last];
        }
        activeNodes.pop();
        activePubkeyIndexes.pop();
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
        uint256 totalNodes = activeNodes.length;
        assertEq(target.getTotalNodes(), totalNodes, "total nodes");
        assertEq(blob.getNodesLength(), totalNodes, "blob length");

        for (uint256 i; i < totalNodes; ++i) {
            LibSecp256k1.Point memory expected = pubkeys[activePubkeyIndexes[i]];
            LibSecp256k1.Point memory stored = blob.getNode(i);
            address node = stored.toAddress();

            assertEq(stored.x, expected.x, "blob node x");
            assertEq(stored.y, expected.y, "blob node y");
            assertEq(node, activeNodes[i], "blob node address");
            assertEq(target.nodeStatus(node), ACTIVE, "active node status");

            for (uint256 j = i + 1; j < totalNodes; ++j) {
                assertTrue(node != activeNodes[j], "duplicate active node");
            }
        }
    }
}
