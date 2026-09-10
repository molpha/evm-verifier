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

    function test_constructor_initializesOwnerBufferAndEmptyRegistry() public view {
        assertEq(verifier.owner(), address(this));
        assertEq(verifier.redundancyBuffer(), 2);
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
        new Verifier(address(0), 2);
    }

    function test_constructor_revertsForRedundancyBufferOverMaxNodes() public {
        vm.expectRevert(IVerifier.RedundancyBufferExceedsMax.selector);
        new Verifier(address(this), 257);
    }

    function test_constructor_acceptsMaximumValidRedundancyBuffer() public {
        Verifier maxBufferVerifier = new Verifier(address(this), 256);

        assertEq(maxBufferVerifier.owner(), address(this));
        assertEq(maxBufferVerifier.redundancyBuffer(), 256);
        assertEq(maxBufferVerifier.getRegistryVersion(), 0);
    }

    function test_completeOwnershipHandover_transfersOwnership() public {
        address newOwner = makeAddr("new owner");

        vm.prank(newOwner);
        verifier.requestOwnershipHandover();

        vm.expectEmit(true, true, false, true, address(verifier));
        emit Ownable.OwnershipTransferred(address(this), newOwner);
        verifier.completeOwnershipHandover(newOwner);

        assertEq(verifier.owner(), newOwner);

        vm.prank(newOwner);
        verifier.setRedundancyBuffer(7);
        assertEq(verifier.redundancyBuffer(), 7);
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

    function test_setRedundancyBuffer_updatesValueEmitsEventAndIncrementsVersion() public {
        uint256 versionBefore = verifier.getRegistryVersion();

        vm.expectEmit(false, false, false, true, address(verifier));
        emit IVerifier.LogRedundancyBufferUpdated(5);
        verifier.setRedundancyBuffer(5);

        assertEq(verifier.redundancyBuffer(), 5);
        assertEq(verifier.getRegistryVersion(), versionBefore + 1);
    }

    function test_setRedundancyBuffer_acceptsMaximumValidBuffer() public {
        verifier.setRedundancyBuffer(256);

        assertEq(verifier.redundancyBuffer(), 256);
    }

    /// @dev The buffer is stored per registry version, so every mutation that publishes a new
    ///      version has to carry the current value across.
    function test_setRedundancyBuffer_carriesForwardAcrossRegistryVersions() public {
        verifier.setRedundancyBuffer(9);
        assertEq(verifier.getRegistryVersion(), 1);

        _addNodes(verifier, 3);
        assertEq(verifier.redundancyBuffer(), 9, "after addNode");
        assertEq(verifier.getRegistryVersion(), 4);

        _removeNode(verifier, 0);
        assertEq(verifier.redundancyBuffer(), 9, "after removeNode");
        assertEq(verifier.getRegistryVersion(), 5);
    }

    function test_setRedundancyBuffer_preservesHistoricalBufferAtOldVersion() public {
        _addNodes(verifier, 5);
        uint256 historicalVersion = verifier.getRegistryVersion();
        assertEq(verifier.redundancyBuffer(), 2);

        // Stay inside [activatesAt, retiredAt + PREVIOUS_GRACE] after the buffer bump.
        (IVerifier.AttestationPayload memory historicalUpdate, IVerifier.SchnorrSignature memory schnorr) =
            _buildVerifyCall(verifier, 3, bytes32("historical buffer"), bytes32("value"), uint64(block.timestamp + 30));

        verifier.setRedundancyBuffer(0);
        assertEq(verifier.getRegistryVersion(), historicalVersion + 1);
        assertEq(verifier.redundancyBuffer(), 0);
        assertEq(historicalUpdate.registryVersion, historicalVersion);
        assertEq(verifier.retiredAt(historicalVersion), block.timestamp);

        _assertVerifyOk(verifier, historicalUpdate, schnorr);
    }

    function test_setRedundancyBuffer_revertsForBufferOverMaxNodes() public {
        vm.expectRevert(IVerifier.RedundancyBufferExceedsMax.selector);
        verifier.setRedundancyBuffer(257);
    }

    function test_setRedundancyBuffer_revertsForNonOwner() public {
        vm.prank(makeAddr("caller"));
        vm.expectRevert(Ownable.Unauthorized.selector);
        verifier.setRedundancyBuffer(1);
    }

    function test_registryRoot_chainsAcrossAddRemoveAndBufferChanges() public {
        bytes32 prevRoot = verifier.getRegistryRoot();
        assertEq(prevRoot, GENESIS_ROOT);

        _addNodes(verifier, 1);
        uint256 version = verifier.getRegistryVersion();
        bytes32 commitment = _keysCommitmentAt(verifier);
        uint256 activatesAtTs = verifier.activatesAt(version);
        bytes32 expectedRoot = _expectedRegistryRoot(prevRoot, version, commitment, 1, 2, activatesAtTs);
        assertEq(verifier.getRegistryRoot(), expectedRoot);

        prevRoot = expectedRoot;
        vm.warp(block.timestamp + 1);
        _appendNode(verifier, 2);
        version = verifier.getRegistryVersion();
        commitment = _keysCommitmentAt(verifier);
        activatesAtTs = verifier.activatesAt(version);
        expectedRoot = _expectedRegistryRoot(prevRoot, version, commitment, 2, 2, activatesAtTs);
        assertEq(verifier.getRegistryRoot(), expectedRoot);

        prevRoot = expectedRoot;
        vm.warp(block.timestamp + 1);
        verifier.setRedundancyBuffer(5);
        version = verifier.getRegistryVersion();
        activatesAtTs = verifier.activatesAt(version);
        expectedRoot = _expectedRegistryRoot(prevRoot, version, commitment, 2, 5, activatesAtTs);
        assertEq(verifier.getRegistryRoot(), expectedRoot);

        prevRoot = expectedRoot;
        vm.warp(block.timestamp + 1);
        _removeNode(verifier, 0);
        version = verifier.getRegistryVersion();
        commitment = _keysCommitmentAt(verifier);
        activatesAtTs = verifier.activatesAt(version);
        expectedRoot = _expectedRegistryRoot(prevRoot, version, commitment, 1, 5, activatesAtTs);
        assertEq(verifier.getRegistryRoot(), expectedRoot);
        assertTrue(verifier.getRegistryRoot(0) != verifier.getRegistryRoot(1));
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
        verifier.setRedundancyBuffer(3);

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
        // Boundary: nodeCount=256, buffer=256, activatesAt=2^40-1 must still resolve the SSTORE2 pointer.
        _addNodes(verifier, 256);
        assertEq(verifier.getTotalNodes(), 256);

        verifier.setRedundancyBuffer(256);
        assertEq(verifier.redundancyBuffer(), 256);
        assertEq(verifier.getTotalNodes(), 256);

        address pointer = verifier.getRegistryPointer();
        assertTrue(pointer != address(0));
        assertEq(KeysCommitmentLib.commitment(SSTORE2.read(pointer)), _keysCommitmentAt(verifier));
    }
}
