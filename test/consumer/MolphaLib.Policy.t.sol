// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";

import {IVerifier} from "../../src/interfaces/IVerifier.sol";
import {MolphaLib} from "../../src/consumer/MolphaLib.sol";
import {MockVerifier} from "../../src/test-utils/MockVerifier.sol";
import {VerifyCodes} from "../../src/libs/VerifyCodes.sol";
import {MolphaLibHarness} from "./MolphaLibHarness.sol";

/// @notice Every branch of the policy check order, for both kinds and both call styles.
contract MolphaLibPolicyTest is Test {
    bytes32 internal constant SOURCE = keccak256("MOLPHA_TEST_SOURCE");
    bytes32 internal constant OTHER_SOURCE = keccak256("MOLPHA_OTHER_SOURCE");
    uint32 internal constant MIN_SIGS = 5;

    MolphaLibHarness internal harness;
    MockVerifier internal mock;
    IVerifier internal v;

    function setUp() public {
        harness = new MolphaLibHarness();
        mock = new MockVerifier();
        v = IVerifier(address(mock));
    }

    function _policy() internal pure returns (MolphaLib.Policy memory) {
        return MolphaLib.Policy({sourceId: SOURCE, minSignatures: MIN_SIGS, maxAge: MolphaLib.NO_MAX_AGE});
    }

    function _att(bytes32 sourceId, uint32 signaturesRequired, bytes32 value)
        internal
        pure
        returns (IVerifier.Attestation memory)
    {
        return IVerifier.Attestation({
            payload: IVerifier.AttestationPayload({
                value: value,
                sourceId: sourceId,
                registryVersion: 1,
                signaturesRequired: signaturesRequired,
                canonicalTimestamp: 1_700_000_000
            }),
            signature: IVerifier.SchnorrSignature({
                signature: bytes32(uint256(1)), commitment: address(1), signersBitmap: 31
            })
        });
    }

    function _ok() internal pure returns (IVerifier.Attestation memory) {
        return _att(SOURCE, MIN_SIGS, bytes32(uint256(1234)));
    }

    // ---------------- policy sanity ----------------

    function test_zeroSourceIdIsInvalidPolicy() public {
        MolphaLib.Policy memory p = _policy();
        p.sourceId = bytes32(0);
        (bool ok, uint8 code) = harness.isValid(v, _ok(), p);
        assertFalse(ok);
        assertEq(code, MolphaLib.L_INVALID_POLICY);

        vm.expectRevert(MolphaLib.InvalidPolicy.selector);
        harness.requireValid(v, _ok(), p);
    }

    function test_zeroMinSignaturesIsInvalidPolicy() public {
        MolphaLib.Policy memory p = _policy();
        p.minSignatures = 0;
        (bool ok, uint8 code) = harness.isValid(v, _ok(), p);
        assertFalse(ok);
        assertEq(code, MolphaLib.L_INVALID_POLICY);

        vm.expectRevert(MolphaLib.InvalidPolicy.selector);
        harness.requireValid(v, _ok(), p);
    }

    function test_bothZeroIsInvalidPolicy() public {
        MolphaLib.Policy memory p = MolphaLib.Policy({sourceId: bytes32(0), minSignatures: 0, maxAge: 0});
        (, uint8 code) = harness.isValid(v, _ok(), p);
        assertEq(code, MolphaLib.L_INVALID_POLICY);
    }

    // ---------------- source binding ----------------

    function test_wrongSourceIsRejected() public {
        IVerifier.Attestation memory att = _att(OTHER_SOURCE, MIN_SIGS, bytes32(uint256(1)));
        (bool ok, uint8 code) = harness.isValid(v, att, _policy());
        assertFalse(ok);
        assertEq(code, MolphaLib.L_WRONG_SOURCE);

        vm.expectRevert(abi.encodeWithSelector(MolphaLib.WrongSource.selector, SOURCE, OTHER_SOURCE));
        harness.requireValid(v, att, _policy());
    }

    // ---------------- threshold floor ----------------

    function test_thresholdBelowPolicyIsRejected() public {
        IVerifier.Attestation memory att = _att(SOURCE, MIN_SIGS - 1, bytes32(uint256(1)));
        (bool ok, uint8 code) = harness.isValid(v, att, _policy());
        assertFalse(ok);
        assertEq(code, MolphaLib.L_THRESHOLD_POLICY);

        vm.expectRevert(abi.encodeWithSelector(MolphaLib.ThresholdBelowPolicy.selector, MIN_SIGS, MIN_SIGS - 1));
        harness.requireValid(v, att, _policy());
    }

    function test_thresholdEqualToPolicyPasses() public view {
        (bool ok, uint8 code) = harness.isValid(v, _att(SOURCE, MIN_SIGS, bytes32(0)), _policy());
        assertTrue(ok);
        assertEq(code, VerifyCodes.R_OK);
    }

    function test_thresholdAbovePolicyPasses() public view {
        (bool ok,) = harness.isValid(v, _att(SOURCE, MIN_SIGS + 10, bytes32(0)), _policy());
        assertTrue(ok);
    }

    // ---------------- verifier passthrough ----------------

    function test_verifierFailureCodeIsPassedThroughVerbatim() public {
        mock.setResult(false, VerifyCodes.R_BAD_SIGNATURE);
        (bool ok, uint8 code) = harness.isValid(v, _ok(), _policy());
        assertFalse(ok);
        assertEq(code, VerifyCodes.R_BAD_SIGNATURE);

        vm.expectRevert(abi.encodeWithSelector(MolphaLib.VerifyFailed.selector, VerifyCodes.R_BAD_SIGNATURE));
        harness.requireValid(v, _ok(), _policy());
    }

    function test_verifierSuccessPasses() public {
        mock.setResult(true, VerifyCodes.R_OK);
        (bool ok, uint8 code) = harness.isValid(v, _ok(), _policy());
        assertTrue(ok);
        assertEq(code, VerifyCodes.R_OK);
        harness.requireValid(v, _ok(), _policy());
    }

    // ---------------- kind B digest binding ----------------

    function test_kindBMatchingDigestPasses() public view {
        bytes memory fields = abi.encode(uint256(7), bytes32("x"), "hello");
        IVerifier.Attestation memory att = _att(SOURCE, MIN_SIGS, keccak256(fields));
        (bool ok, uint8 code) = harness.isValidFields(v, att, _policy(), fields);
        assertTrue(ok);
        assertEq(code, VerifyCodes.R_OK);
    }

    function test_kindBMismatchedDigestIsRejected() public {
        bytes memory fields = abi.encode(uint256(7));
        bytes32 committed = keccak256(abi.encode(uint256(8)));
        IVerifier.Attestation memory att = _att(SOURCE, MIN_SIGS, committed);

        (bool ok, uint8 code) = harness.isValidFields(v, att, _policy(), fields);
        assertFalse(ok);
        assertEq(code, MolphaLib.L_PAYLOAD_MISMATCH);

        vm.expectRevert(abi.encodeWithSelector(MolphaLib.PayloadMismatch.selector, committed, keccak256(fields)));
        harness.requireValidFields(v, att, _policy(), fields);
    }

    function test_kindBEmptyFieldsBindToKeccakOfEmpty() public view {
        IVerifier.Attestation memory att = _att(SOURCE, MIN_SIGS, keccak256(""));
        (bool ok,) = harness.isValidFields(v, att, _policy(), "");
        assertTrue(ok);
    }

    function test_kindBPolicyChecksStillRunFirst() public {
        // A digest mismatch AND a wrong source: source wins, because it is checked earlier.
        IVerifier.Attestation memory att = _att(OTHER_SOURCE, MIN_SIGS, keccak256("committed"));
        (, uint8 code) = harness.isValidFields(v, att, _policy(), "different");
        assertEq(code, MolphaLib.L_WRONG_SOURCE);
    }

    // ---------------- ordering: the part that actually matters ----------------

    function test_sourceIsCheckedBeforeThreshold() public view {
        // Violates both. The earlier check must win.
        IVerifier.Attestation memory att = _att(OTHER_SOURCE, MIN_SIGS - 1, bytes32(0));
        (, uint8 code) = harness.isValid(v, att, _policy());
        assertEq(code, MolphaLib.L_WRONG_SOURCE);
    }

    function test_policySanityIsCheckedBeforeSource() public view {
        MolphaLib.Policy memory p = _policy();
        p.sourceId = bytes32(0);
        // Zero policy source can never equal the attestation's source, so both would fail.
        (, uint8 code) = harness.isValid(v, _att(OTHER_SOURCE, MIN_SIGS, bytes32(0)), p);
        assertEq(code, MolphaLib.L_INVALID_POLICY);
    }

    function test_verifierIsNotCalledWhenAPolicyCheckFails() public {
        // The mock would say yes. The library must never ask.
        mock.setResult(true, VerifyCodes.R_OK);
        IVerifier.Attestation memory att = _att(OTHER_SOURCE, MIN_SIGS, bytes32(0));

        vm.expectCall(address(mock), abi.encodeWithSelector(MockVerifier.verify.selector), 0);
        (bool ok,) = harness.isValid(v, att, _policy());
        assertFalse(ok);
    }

    function test_maxAgeIsForwardedToTheVerifierVerbatim() public {
        MolphaLib.Policy memory p = _policy();
        p.maxAge = 3600;
        IVerifier.Attestation memory att = _ok();

        vm.expectCall(address(mock), abi.encodeCall(IVerifier.verify, (att, 3600)), 1);
        harness.isValid(v, att, p);
    }

    function test_noMaxAgeIsForwardedAsZero() public {
        IVerifier.Attestation memory att = _ok();
        vm.expectCall(address(mock), abi.encodeCall(IVerifier.verify, (att, 0)), 1);
        harness.isValid(v, att, _policy());
    }

    /// @dev The guard against `_checkPolicy` and `_requirePolicy` drifting apart: for every
    ///      fixture, `isValid`'s code and `requireValid`'s revert must name the same branch.
    function test_isValidAndRequireValidAgreeOnEveryBranch() public {
        MolphaLib.Policy memory good = _policy();
        MolphaLib.Policy memory zeroSource = _policy();
        zeroSource.sourceId = bytes32(0);
        MolphaLib.Policy memory zeroMin = _policy();
        zeroMin.minSignatures = 0;

        _assertAgreement(zeroSource, _ok(), MolphaLib.L_INVALID_POLICY);
        _assertAgreement(zeroMin, _ok(), MolphaLib.L_INVALID_POLICY);
        _assertAgreement(good, _att(OTHER_SOURCE, MIN_SIGS, bytes32(0)), MolphaLib.L_WRONG_SOURCE);
        _assertAgreement(good, _att(SOURCE, MIN_SIGS - 1, bytes32(0)), MolphaLib.L_THRESHOLD_POLICY);

        mock.setResult(false, VerifyCodes.R_STALE);
        _assertAgreement(good, _ok(), VerifyCodes.R_STALE);
    }

    function _assertAgreement(MolphaLib.Policy memory p, IVerifier.Attestation memory att, uint8 expectedCode) private {
        (bool ok, uint8 code) = harness.isValid(v, att, p);
        assertFalse(ok, "isValid should fail");
        assertEq(code, expectedCode, "isValid code");

        vm.expectPartialRevert(_expectedRevert(expectedCode));
        harness.requireValid(v, att, p);
    }

    /// @dev Selector-only: this test asserts the two paths pick the same BRANCH. The parameter
    ///      values carried by each error are asserted in the per-branch tests above.
    function _expectedRevert(uint8 code) private pure returns (bytes4) {
        if (code == MolphaLib.L_INVALID_POLICY) return MolphaLib.InvalidPolicy.selector;
        if (code == MolphaLib.L_WRONG_SOURCE) return MolphaLib.WrongSource.selector;
        if (code == MolphaLib.L_THRESHOLD_POLICY) return MolphaLib.ThresholdBelowPolicy.selector;
        if (code == MolphaLib.L_PAYLOAD_MISMATCH) return MolphaLib.PayloadMismatch.selector;
        return MolphaLib.VerifyFailed.selector;
    }
}
