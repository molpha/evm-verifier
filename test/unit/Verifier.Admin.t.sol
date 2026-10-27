// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Ownable} from "solady/auth/Ownable.sol";
import {SSTORE2} from "solady/utils/SSTORE2.sol";
import {IVerifier} from "../../src/interfaces/IVerifier.sol";
import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";
import {KeysCommitmentLib} from "../../src/libs/KeysCommitmentLib.sol";
import {Verifier} from "../../src/Verifier.sol";
import {VerifierTestBase} from "../shared/VerifierTestBase.sol";

contract VerifierAdminTest is VerifierTestBase {
    using LibSecp256k1 for LibSecp256k1.Point;

    function test_constructor_initializesOwnerAndEmptyRegistry() public view {
        assertEq(verifier.owner(), address(this));
        assertEq(verifier.getRegistryVersion(), 0);
        assertEq(verifier.getTotalNodes(), 0);
        assertEq(verifier.getRegistryPointer(), verifier.getRegistryPointer(0));
        assertTrue(verifier.getRegistryPointer() != address(0));
        assertEq(verifier.getRegistryRoot(), GENESIS_ROOT);
        assertEq(verifier.getRegistryRoot(0), GENESIS_ROOT);
        assertEq(verifier.activatesAt(0), 0);
        assertTrue(verifier.isLatestVersion(0));
        assertEq(_keysCommitmentAt(verifier), KeysCommitmentLib.emptyCommitment());
        assertEq(_keysCommitmentAt(verifier, 0), KeysCommitmentLib.emptyCommitment());
    }

    function test_constructor_revertsForZeroInitialOwner() public {
        vm.expectRevert(IVerifier.ZeroAdmin.selector);
        new Verifier(address(0));
    }

    function test_completeOwnershipHandover_transfersOwnership() public {
        address newOwner = makeAddr("new owner");

        vm.prank(newOwner);
        verifier.requestOwnershipHandover();

        vm.expectEmit(true, true, false, true, address(verifier));
        emit Ownable.OwnershipTransferred(address(this), newOwner);
        verifier.completeOwnershipHandover(newOwner);

        assertEq(verifier.owner(), newOwner);

        // The new owner administers the registry; the old one no longer does.
        bytes memory compressed = LibSecp256k1.compress(LibSecp256k1.mulAffine(LibSecp256k1.G(), _secret(1)));
        IVerifier.SchnorrProof memory pop = _proofOfPossession(address(verifier), compressed, _secret(1));
        vm.expectRevert(Ownable.Unauthorized.selector);
        verifier.addNode(compressed, pop);
        vm.prank(newOwner);
        verifier.addNode(compressed, pop);
        assertEq(verifier.getTotalNodes(), 1);
    }

    function test_completeOwnershipHandover_revertsWithoutRequest() public {
        address newOwner = makeAddr("new owner");

        vm.expectRevert(Ownable.NoHandoverRequest.selector);
        verifier.completeOwnershipHandover(newOwner);
    }

    function test_transferOwnership_revertsForZeroAddress() public {
        vm.expectRevert(Ownable.NewOwnerIsZeroAddress.selector);
        verifier.transferOwnership(address(0));
    }

    function test_completeOwnershipHandover_revertsForNonOwner() public {
        address newOwner = makeAddr("new owner");

        vm.prank(newOwner);
        verifier.requestOwnershipHandover();

        vm.prank(makeAddr("caller"));
        vm.expectRevert(Ownable.Unauthorized.selector);
        verifier.completeOwnershipHandover(newOwner);
    }

    /// @dev A removal publishes a new version, and a version already published keeps verifying
    ///      what it verified, for its grace window.
    function test_removeNode_keepsThePreviousVersionVerifyingForTheGraceWindow() public {
        _addNodes(verifier, 5);
        uint256 historicalVersion = verifier.getRegistryVersion();

        // Stay inside [activatesAt, retiredAt + PREVIOUS_GRACE] after the removal.
        (IVerifier.AttestationPayload memory historicalUpdate, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("historical"), bytes32("value"), _ms(block.timestamp + 30));

        _removeNode(verifier, 4);
        assertEq(verifier.getRegistryVersion(), historicalVersion + 1);
        assertEq(historicalUpdate.registryVersion, historicalVersion);
        assertEq(verifier.retiredAt(historicalVersion), block.timestamp);

        _assertVerifyOk(verifier, historicalUpdate, schnorr);
    }

    function test_registryRoot_chainsAcrossAddAndRemove() public {
        bytes32 prevRoot = verifier.getRegistryRoot();
        assertEq(prevRoot, GENESIS_ROOT);

        _addNodes(verifier, 1);
        uint256 version = verifier.getRegistryVersion();
        bytes32 commitment = _keysCommitmentAt(verifier);
        uint256 activatesAtTs = verifier.activatesAt(version);
        bytes32 expectedRoot = _expectedRegistryRoot(prevRoot, version, commitment, 1, activatesAtTs);
        assertEq(verifier.getRegistryRoot(), expectedRoot);

        prevRoot = expectedRoot;
        vm.warp(block.timestamp + 1);
        _appendNode(verifier, 2);
        version = verifier.getRegistryVersion();
        commitment = _keysCommitmentAt(verifier);
        activatesAtTs = verifier.activatesAt(version);
        expectedRoot = _expectedRegistryRoot(prevRoot, version, commitment, 2, activatesAtTs);
        assertEq(verifier.getRegistryRoot(), expectedRoot);

        // Removing slot 0 leaves a hole: the slot count the root commits to stays 2.
        prevRoot = expectedRoot;
        vm.warp(block.timestamp + 1);
        _removeNode(verifier, 0);
        version = verifier.getRegistryVersion();
        commitment = _keysCommitmentAt(verifier);
        activatesAtTs = verifier.activatesAt(version);
        expectedRoot = _expectedRegistryRoot(prevRoot, version, commitment, 2, activatesAtTs);
        assertEq(verifier.getRegistryRoot(), expectedRoot);
        assertTrue(verifier.getRegistryRoot(0) != verifier.getRegistryRoot(1));

        // Removing the last node trims the trailing holes behind it: the count falls to 0.
        prevRoot = expectedRoot;
        vm.warp(block.timestamp + 1);
        _removeNode(verifier, 1);
        version = verifier.getRegistryVersion();
        commitment = _keysCommitmentAt(verifier);
        activatesAtTs = verifier.activatesAt(version);
        expectedRoot = _expectedRegistryRoot(prevRoot, version, commitment, 0, activatesAtTs);
        assertEq(verifier.getRegistryRoot(), expectedRoot);
        assertEq(commitment, KeysCommitmentLib.emptyCommitment());
    }

    function test_getRegistryRoot_revertsForUnknownVersion() public {
        vm.expectRevert(IVerifier.InvalidRegistryVersion.selector);
        verifier.getRegistryRoot(1);
    }

    function test_activatesAt_stampsBlockTimestampOnTransition() public {
        vm.warp(BASE_TIME + 100);
        _addNodes(verifier, 1);

        assertEq(verifier.activatesAt(1), BASE_TIME + 100);
        assertEq(verifier.activatesAt(0), 0);
    }

    function test_activatesAt_revertsForUnknownVersion() public {
        vm.expectRevert(IVerifier.InvalidRegistryVersion.selector);
        verifier.activatesAt(1);

        vm.expectRevert(IVerifier.InvalidRegistryVersion.selector);
        verifier.activatesAt(type(uint256).max);
    }

    function test_retiredAt_equalsSuccessorActivatesAt() public {
        _addNodes(verifier, 1);
        uint256 v1 = verifier.getRegistryVersion();
        uint256 activatesV1 = verifier.activatesAt(v1);

        vm.warp(block.timestamp + 42);
        _appendNode(verifier, 2);

        assertEq(verifier.retiredAt(v1), activatesV1 + 42);
        assertEq(verifier.retiredAt(v1), verifier.activatesAt(v1 + 1));
    }

    function test_retiredAt_revertsForCurrentVersion() public {
        _addNodes(verifier, 1);
        uint256 current = verifier.getRegistryVersion();
        vm.expectRevert(IVerifier.InvalidRegistryVersion.selector);
        verifier.retiredAt(current);
    }

    function test_entryPacking_pointerSurvivesMaxHighFields() public {
        // Boundary: nodeCount=256 must still resolve the SSTORE2 pointer.
        _addNodes(verifier, 256);
        assertEq(verifier.getTotalNodes(), 256);

        address pointer = verifier.getRegistryPointer();
        assertTrue(pointer != address(0));
        assertEq(KeysCommitmentLib.commitment(SSTORE2.read(pointer)), _keysCommitmentAt(verifier));
    }
}
