// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

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

        assertTrue(verifier.isNode(node));
        assertEq(verifier.getNodeIndex(node), 1);
        assertEq(verifier.nodeIndexes(node), 1);
        assertEq(verifier.nodeKeyX(1), pubkey.x);
        assertEq(verifier.nodeKeyY(1), pubkey.y);
        assertEq(verifier.getTotalNodes(), 1);
        assertEq(verifier.getRegistryVersion(), 1);
        assertEq(verifier.getRegistryPointer(0), initialPointer);
        assertTrue(verifier.getRegistryPointer() != initialPointer);

        (uint256 aggregateX, uint256 aggregateY) = verifier.getAggregateKey();
        assertEq(aggregateX, pubkey.x);
        assertEq(aggregateY, pubkey.y);
    }

    function test_addNode_revertsForDuplicateNode() public {
        _addNodes(verifier, 1);
        bytes memory compressed = LibSecp256k1.compress(pubkeys[0]);
        IVerifier.SchnorrProof memory proof = _proofOfPossession(address(verifier), compressed, secrets[0]);

        vm.expectRevert(IVerifier.NodeAlreadyAdded.selector);
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
    }

    function test_addNode_revertsForNonAdmin() public {
        uint256 secret = _secret(1);
        LibSecp256k1.Point memory pubkey = LibSecp256k1.mulAffine(LibSecp256k1.G(), secret);
        bytes memory compressed = LibSecp256k1.compress(pubkey);
        IVerifier.SchnorrProof memory proof = _proofOfPossession(address(verifier), compressed, secret);

        vm.prank(makeAddr("caller"));
        vm.expectRevert(IVerifier.NotProtocolAdmin.selector);
        verifier.addNode(compressed, proof);
    }

    function test_removeNode_resetsAggregateWhenRemovingOnlyNode() public {
        _addNodes(verifier, 1);
        address node = pubkeys[0].toAddress();

        vm.expectEmit(true, false, false, false, address(verifier));
        emit IVerifier.LogNodeRemoved(node, 0, address(0));
        verifier.removeNode(node);

        assertFalse(verifier.isNode(node));
        assertEq(verifier.getNodeIndex(node), 0);
        assertEq(verifier.getTotalNodes(), 0);
        assertEq(verifier.nodeKeyX(1), 0);
        assertEq(verifier.nodeKeyY(1), 0);

        (uint256 aggregateX, uint256 aggregateY) = verifier.getAggregateKey();
        assertEq(aggregateX, 0);
        assertEq(aggregateY, 0);
    }

    function test_removeNode_swapsLastNodeIntoRemovedMiddleIndex() public {
        _addNodes(verifier, 3);
        address removed = pubkeys[1].toAddress();
        address swapped = pubkeys[2].toAddress();

        verifier.removeNode(removed);

        assertFalse(verifier.isNode(removed));
        assertEq(verifier.getNodeIndex(swapped), 2);
        assertEq(verifier.nodeKeyX(2), pubkeys[2].x);
        assertEq(verifier.nodeKeyY(2), pubkeys[2].y);
        assertEq(verifier.nodeKeyX(3), 0);
        assertEq(verifier.nodeKeyY(3), 0);
        assertEq(verifier.getTotalNodes(), 2);

        (uint256 x, uint256 y, uint256 z) =
            LibSecp256k1.addAffinePointToXYZ(pubkeys[0].x, pubkeys[0].y, 1, pubkeys[2].x, pubkeys[2].y);
        LibSecp256k1.Point memory expected = LibSecp256k1.toAffineModexpXYZ(x, y, z);
        (uint256 aggregateX, uint256 aggregateY) = verifier.getAggregateKey();
        assertEq(aggregateX, expected.x);
        assertEq(aggregateY, expected.y);
    }

    function test_removeNode_removesLastWithoutReordering() public {
        _addNodes(verifier, 3);
        address first = pubkeys[0].toAddress();
        address second = pubkeys[1].toAddress();
        address last = pubkeys[2].toAddress();

        verifier.removeNode(last);

        assertEq(verifier.getNodeIndex(first), 1);
        assertEq(verifier.getNodeIndex(second), 2);
        assertEq(verifier.getNodeIndex(last), 0);
        assertEq(verifier.getTotalNodes(), 2);
    }

    function test_removeNode_allowsRemovedNodeToBeRegisteredAgain() public {
        _addNodes(verifier, 2);
        address node = pubkeys[0].toAddress();
        bytes memory compressed = LibSecp256k1.compress(pubkeys[0]);
        IVerifier.SchnorrProof memory proof = _proofOfPossession(address(verifier), compressed, secrets[0]);

        verifier.removeNode(node);
        verifier.addNode(compressed, proof);

        assertTrue(verifier.isNode(node));
        assertEq(verifier.getNodeIndex(node), 2);
        assertEq(verifier.getTotalNodes(), 2);
    }

    function test_removeNode_revertsForUnknownNode() public {
        vm.expectRevert(IVerifier.NotNode.selector);
        verifier.removeNode(makeAddr("unknown node"));
    }

    function test_removeNode_revertsForNonAdmin() public {
        _addNodes(verifier, 1);

        vm.prank(makeAddr("caller"));
        vm.expectRevert(IVerifier.NotProtocolAdmin.selector);
        verifier.removeNode(pubkeys[0].toAddress());
    }

    function test_registryPointersRemainImmutableAcrossMutations() public {
        address pointer0 = verifier.getRegistryPointer();
        _addNodes(verifier, 2);
        address pointer1 = verifier.getRegistryPointer(1);
        address pointer2 = verifier.getRegistryPointer(2);

        verifier.removeNode(pubkeys[0].toAddress());

        assertEq(verifier.getRegistryVersion(), 3);
        assertEq(verifier.getRegistryPointer(0), pointer0);
        assertEq(verifier.getRegistryPointer(1), pointer1);
        assertEq(verifier.getRegistryPointer(2), pointer2);
        assertTrue(verifier.getRegistryPointer(3) != pointer2);
    }

    function test_getRegistryPointer_revertsForUnknownVersion() public {
        vm.expectRevert();
        verifier.getRegistryPointer(1);
    }

    function test_getNodesSetHash_isStableUntilRegistryChanges() public {
        bytes32 emptyHash = verifier.getNodesSetHash();
        assertEq(verifier.getNodesSetHash(), emptyHash);

        _addNodes(verifier, 1);
        bytes32 oneNodeHash = verifier.getNodesSetHash();
        assertTrue(oneNodeHash != emptyHash);
        assertEq(verifier.getNodesSetHash(), oneNodeHash);
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
                target.removeNode(activeNodes[removeIndex]);
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

        verifier.removeNode(removed);

        assertFalse(verifier.isNode(removed));
        assertEq(verifier.getTotalNodes(), 255);
        assertEq(verifier.getNodeIndex(swappedFromIndex256), 1);
        assertEq(verifier.nodeKeyX(1), pubkeys[255].x);
        assertEq(verifier.nodeKeyY(1), pubkeys[255].y);
        assertEq(verifier.nodeKeyX(256), 0);
        assertEq(verifier.nodeKeyY(256), 0);
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
        }

        bytes memory blob = SSTORE2.read(target.getRegistryPointer());
        uint256 totalNodes = activeNodes.length;
        assertEq(target.getTotalNodes(), totalNodes, "total nodes");
        assertEq(blob.getNodesLength(), totalNodes + 1, "blob length");

        for (uint256 i; i < totalNodes; ++i) {
            LibSecp256k1.Point memory expected = pubkeys[activePubkeyIndexes[i]];
            LibSecp256k1.Point memory stored = blob.getNode(i + 1);
            address node = stored.toAddress();

            assertEq(stored.x, expected.x, "blob node x");
            assertEq(stored.y, expected.y, "blob node y");
            assertEq(node, activeNodes[i], "blob node address");
            assertTrue(target.isNode(node), "active node");
            assertEq(target.nodeIndexes(node), i + 1, "node index");
            assertEq(target.getNodeIndex(node), i + 1, "get node index");
            assertEq(target.nodeKeyX(i + 1), stored.x, "node key x");
            assertEq(target.nodeKeyY(i + 1), stored.y, "node key y");

            for (uint256 j = i + 1; j < totalNodes; ++j) {
                assertTrue(node != activeNodes[j], "duplicate active node");
            }
        }

        LibSecp256k1.Point memory expectedAggregate = _recomputeActiveAggregate();
        LibSecp256k1.Point memory storedAggregate = blob.getNode(0);
        (uint256 aggregateX, uint256 aggregateY) = target.getAggregateKey();

        assertEq(storedAggregate.x, expectedAggregate.x, "stored aggregate x");
        assertEq(storedAggregate.y, expectedAggregate.y, "stored aggregate y");
        assertEq(aggregateX, expectedAggregate.x, "aggregate x");
        assertEq(aggregateY, expectedAggregate.y, "aggregate y");

        if (totalNodes == 0) {
            assertEq(target.nodeKeyX(1), 0, "empty node key x");
            assertEq(target.nodeKeyY(1), 0, "empty node key y");
        } else {
            assertEq(target.nodeKeyX(totalNodes + 1), 0, "stale node key x");
            assertEq(target.nodeKeyY(totalNodes + 1), 0, "stale node key y");
        }
    }

    function _recomputeActiveAggregate() internal view returns (LibSecp256k1.Point memory aggregate) {
        if (activePubkeyIndexes.length == 0) {
            return LibSecp256k1.ZERO_POINT();
        }

        aggregate = pubkeys[activePubkeyIndexes[0]];
        for (uint256 i = 1; i < activePubkeyIndexes.length; ++i) {
            LibSecp256k1.Point memory next = pubkeys[activePubkeyIndexes[i]];
            (uint256 x, uint256 y, uint256 z) =
                LibSecp256k1.addAffinePointToXYZ(aggregate.x, aggregate.y, 1, next.x, next.y);
            aggregate = LibSecp256k1.toAffineModexpXYZ(x, y, z);
        }
    }
}
