// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IVerifier} from "../../src/interfaces/IVerifier.sol";
import {Verifier} from "../../src/Verifier.sol";
import {VerifierTestBase} from "../shared/VerifierTestBase.sol";

contract VerifierAdminTest is VerifierTestBase {
    function test_constructor_initializesAdminBufferAndEmptyRegistry() public view {
        assertEq(verifier.protocolAdmin(), address(this));
        assertEq(verifier.redundancyBuffer(), 2);
        assertEq(verifier.getRegistryVersion(), 0);
        assertEq(verifier.getTotalNodes(), 0);
        assertEq(verifier.getRegistryPointer(), verifier.getRegistryPointer(0));
        assertTrue(verifier.getRegistryPointer() != address(0));

        (uint256 x, uint256 y) = verifier.getAggregateKey();
        assertEq(x, 0);
        assertEq(y, 0);
    }

    function test_constructor_revertsForZeroInitialAdmin() public {
        vm.expectRevert(IVerifier.ZeroAdmin.selector);
        new Verifier(address(0), 2);
    }

    function test_constructor_revertsForRedundancyBufferOverMaxNodes() public {
        vm.expectRevert(IVerifier.RedundancyBufferExceedsMax.selector);
        new Verifier(address(this), 257);
    }

    function test_constructor_acceptsMaximumValidRedundancyBuffer() public {
        Verifier maxBufferVerifier = new Verifier(address(this), 256);

        assertEq(maxBufferVerifier.protocolAdmin(), address(this));
        assertEq(maxBufferVerifier.redundancyBuffer(), 256);
        assertEq(maxBufferVerifier.getRegistryVersion(), 0);
    }

    function test_transferProtocolAdmin_updatesRoleAndEmitsEvent() public {
        address newAdmin = makeAddr("new admin");

        vm.expectEmit(true, true, false, true, address(verifier));
        emit IVerifier.LogProtocolAdminTransferred(address(this), newAdmin);
        verifier.transferProtocolAdmin(newAdmin);

        assertEq(verifier.protocolAdmin(), newAdmin);

        vm.prank(newAdmin);
        verifier.setRedundancyBuffer(7);
        assertEq(verifier.redundancyBuffer(), 7);
    }

    function test_transferProtocolAdmin_revertsForZeroAddress() public {
        vm.expectRevert(IVerifier.ZeroAdmin.selector);
        verifier.transferProtocolAdmin(address(0));
    }

    function test_transferProtocolAdmin_revertsForNonAdmin() public {
        vm.prank(makeAddr("caller"));
        vm.expectRevert(IVerifier.NotProtocolAdmin.selector);
        verifier.transferProtocolAdmin(makeAddr("new admin"));
    }

    function test_setRedundancyBuffer_updatesValueAndEmitsEvent() public {
        vm.expectEmit(false, false, false, true, address(verifier));
        emit IVerifier.LogRedundancyBufferUpdated(5);
        verifier.setRedundancyBuffer(5);

        assertEq(verifier.redundancyBuffer(), 5);
    }

    function test_setRedundancyBuffer_acceptsMaximumValidBuffer() public {
        verifier.setRedundancyBuffer(256);

        assertEq(verifier.redundancyBuffer(), 256);
    }

    function test_setRedundancyBuffer_revertsForBufferOverMaxNodes() public {
        vm.expectRevert(IVerifier.RedundancyBufferExceedsMax.selector);
        verifier.setRedundancyBuffer(257);
    }

    function test_setRedundancyBuffer_revertsForNonAdmin() public {
        vm.prank(makeAddr("caller"));
        vm.expectRevert(IVerifier.NotProtocolAdmin.selector);
        verifier.setRedundancyBuffer(1);
    }
}
