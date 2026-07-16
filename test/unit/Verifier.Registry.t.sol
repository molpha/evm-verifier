// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Verifier} from "../../src/Verifier.sol";
import {IVerifier} from "../../src/interfaces/IVerifier.sol";
import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";
import {VerifierTestBase} from "../shared/VerifierTestBase.sol";

contract VerifierRegistryTest is VerifierTestBase {
    using LibSecp256k1 for LibSecp256k1.Point;

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

        vm.expectRevert(bytes("Node already added"));
        verifier.addNode(compressed, proof);
    }

    function test_addNode_revertsForInvalidProofOfPossession() public {
        uint256 secret = _secret(1);
        LibSecp256k1.Point memory pubkey = LibSecp256k1.mulAffine(LibSecp256k1.G(), secret);
        bytes memory compressed = LibSecp256k1.compress(pubkey);
        IVerifier.SchnorrProof memory proof = _proofOfPossession(address(verifier), compressed, secret);
        proof.signature = bytes32(uint256(proof.signature) ^ 1);

        vm.expectRevert(bytes("Invalid PoP"));
        verifier.addNode(compressed, proof);
    }

    function test_addNode_rejectsProofBoundToDifferentVerifier() public {
        Verifier other = new Verifier(address(this), 2);
        uint256 secret = _secret(1);
        LibSecp256k1.Point memory pubkey = LibSecp256k1.mulAffine(LibSecp256k1.G(), secret);
        bytes memory compressed = LibSecp256k1.compress(pubkey);
        IVerifier.SchnorrProof memory proof = _proofOfPossession(address(verifier), compressed, secret);

        vm.expectRevert(bytes("Invalid PoP"));
        other.addNode(compressed, proof);
    }

    function test_addNode_revertsForMalformedCompressedKeys() public {
        IVerifier.SchnorrProof memory emptyProof;

        vm.expectRevert(bytes("invalid length"));
        verifier.addNode(hex"02", emptyProof);

        vm.expectRevert(bytes("bad prefix"));
        verifier.addNode(abi.encodePacked(bytes1(0x04), bytes32(uint256(1))), emptyProof);

        vm.expectRevert(bytes("x>=p"));
        verifier.addNode(abi.encodePacked(bytes1(0x02), bytes32(LibSecp256k1.fieldP())), emptyProof);
    }

    function test_addNode_revertsForNonAdmin() public {
        uint256 secret = _secret(1);
        LibSecp256k1.Point memory pubkey = LibSecp256k1.mulAffine(LibSecp256k1.G(), secret);
        bytes memory compressed = LibSecp256k1.compress(pubkey);
        IVerifier.SchnorrProof memory proof = _proofOfPossession(address(verifier), compressed, secret);

        vm.prank(makeAddr("caller"));
        vm.expectRevert(bytes("Not protocol admin"));
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
        vm.expectRevert(bytes("Not node"));
        verifier.removeNode(makeAddr("unknown node"));
    }

    function test_removeNode_revertsForNonAdmin() public {
        _addNodes(verifier, 1);

        vm.prank(makeAddr("caller"));
        vm.expectRevert(bytes("Not protocol admin"));
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
}
