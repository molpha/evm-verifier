// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";

import {IVerifier} from "../../src/interfaces/IVerifier.sol";
import {MolphaLib} from "../../src/consumer/MolphaLib.sol";
import {MolphaTestSigner} from "../../src/test-utils/MolphaTestSigner.sol";
import {VerifyCodes} from "../../src/libs/VerifyCodes.sol";
import {MolphaLibHarness} from "./MolphaLibHarness.sol";

/// @notice Exercises the shipped test utility exactly as an integrator would, with real
///         signatures against a real local `Verifier`.
contract MolphaTestSignerTest is Test {
    bytes32 internal constant SOURCE = keccak256("MOLPHA_TEST_SOURCE");
    uint8 internal constant THRESHOLD = 5;

    MolphaTestSigner internal signer;
    MolphaLibHarness internal harness;
    IVerifier internal v;

    function setUp() public {
        vm.warp(1_700_000_000);
        signer = new MolphaTestSigner(2);
        signer.registerNodes(8);
        harness = new MolphaLibHarness();
        v = IVerifier(address(signer.verifier()));
    }

    function _policy() internal pure returns (MolphaLib.Policy memory) {
        return MolphaLib.Policy({sourceId: SOURCE, minSignatures: THRESHOLD, maxAge: MolphaLib.NO_MAX_AGE});
    }

    function test_registersTheRequestedNodeCount() public view {
        assertEq(signer.nodeCount(), 8);
        assertEq(signer.verifier().getTotalNodes(), 8);
        assertEq(signer.verifier().getRegistryVersion(), 8);
    }

    function test_attestationVerifiesAgainstTheRealVerifier() public view {
        IVerifier.Attestation memory att =
            signer.attest(SOURCE, bytes32(uint256(1234)), THRESHOLD, uint64(block.timestamp));
        (bool ok, uint8 code) = v.verify(att, 0);
        assertTrue(ok);
        assertEq(code, VerifyCodes.R_OK);
    }

    function test_attestationSatisfiesMolphaLib() public view {
        IVerifier.Attestation memory att =
            signer.attest(SOURCE, bytes32(uint256(1234)), THRESHOLD, uint64(block.timestamp));
        harness.requireValid(v, att, _policy());
        (bool ok, uint8 code) = harness.isValid(v, att, _policy());
        assertTrue(ok);
        assertEq(code, VerifyCodes.R_OK);
    }

    function test_overSigningStillVerifies() public view {
        IVerifier.Attestation memory att =
            signer.attest(SOURCE, bytes32(uint256(1)), THRESHOLD, THRESHOLD + 2, uint64(block.timestamp));
        (bool ok,) = v.verify(att, 0);
        assertTrue(ok);
        harness.requireValid(v, att, _policy());
    }

    function test_kindBAttestationCommitsToTheEncodedFields() public view {
        bytes memory fields = abi.encode(uint256(42), bytes32("tag"), "payload");
        IVerifier.Attestation memory att = signer.attestFields(SOURCE, fields, THRESHOLD, uint64(block.timestamp));

        assertEq(att.payload.value, keccak256(fields), "value must be the digest");
        harness.requireValidFields(v, att, _policy(), fields);

        (bool ok, uint8 code) = harness.isValidFields(v, att, _policy(), fields);
        assertTrue(ok);
        assertEq(code, VerifyCodes.R_OK);
    }

    function test_kindBRejectsTamperedFields() public {
        bytes memory fields = abi.encode(uint256(42));
        IVerifier.Attestation memory att = signer.attestFields(SOURCE, fields, THRESHOLD, uint64(block.timestamp));

        vm.expectPartialRevert(MolphaLib.PayloadMismatch.selector);
        harness.requireValidFields(v, att, _policy(), abi.encode(uint256(43)));
    }

    function test_attestationStillVerifiesAfterANodeIsRemoved() public {
        signer.removeNode(3);
        assertEq(signer.nodeCount(), 7);

        IVerifier.Attestation memory att =
            signer.attest(SOURCE, bytes32(uint256(9)), THRESHOLD, uint64(block.timestamp));
        (bool ok, uint8 code) = v.verify(att, 0);
        assertTrue(ok, "mirrors must track the registry swap-and-pop");
        assertEq(code, VerifyCodes.R_OK);
    }

    function test_tamperedSignatureIsRejectedByTheVerifier() public {
        IVerifier.Attestation memory att =
            signer.attest(SOURCE, bytes32(uint256(1234)), THRESHOLD, uint64(block.timestamp));
        att.payload.value = bytes32(uint256(9999));

        (bool ok, uint8 code) = v.verify(att, 0);
        assertFalse(ok);
        assertEq(code, VerifyCodes.R_BAD_SIGNATURE);

        vm.expectRevert(abi.encodeWithSelector(MolphaLib.VerifyFailed.selector, VerifyCodes.R_BAD_SIGNATURE));
        harness.requireValid(v, att, _policy());
    }

    function test_staleAttestationIsRejectedUnderAMaxAgePolicy() public {
        IVerifier.Attestation memory att =
            signer.attest(SOURCE, bytes32(uint256(1)), THRESHOLD, uint64(block.timestamp));
        MolphaLib.Policy memory p = _policy();
        p.maxAge = 3600;

        vm.warp(block.timestamp + 3601);
        vm.expectRevert(abi.encodeWithSelector(MolphaLib.VerifyFailed.selector, VerifyCodes.R_STALE));
        harness.requireValid(v, att, p);
    }

    /// @dev `MolphaSigLib` uses no cheatcodes, so the signer works from a plain contract frame.
    function test_signerNeedsNoCheatcodes() public {
        MolphaTestSigner fresh = new MolphaTestSigner(2);
        fresh.registerNodes(4);
        IVerifier.Attestation memory att = fresh.attest(SOURCE, bytes32(uint256(7)), 3, uint64(block.timestamp));
        (bool ok,) = IVerifier(address(fresh.verifier())).verify(att, 0);
        assertTrue(ok);
    }
}
