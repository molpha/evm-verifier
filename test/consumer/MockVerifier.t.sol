// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";

import {IVerifier} from "../../src/interfaces/IVerifier.sol";
import {MockVerifier} from "../../src/test-utils/MockVerifier.sol";
import {VerifyCodes} from "../../src/libs/VerifyCodes.sol";

contract MockVerifierTest is Test {
    MockVerifier internal mock;

    function setUp() public {
        mock = new MockVerifier();
    }

    function _att(bytes32 sourceId) internal pure returns (IVerifier.Attestation memory) {
        return IVerifier.Attestation({
            payload: IVerifier.AttestationPayload({
                value: bytes32(uint256(1)),
                sourceId: sourceId,
                registryVersion: 1,
                signaturesRequired: 5,
                canonicalTimestamp: 1_700_000_000
            }),
            signature: IVerifier.SchnorrSignature({
                signature: bytes32(uint256(1)), commitment: address(1), signersBitmap: 31
            })
        });
    }

    /// @dev The mock does not inherit `IVerifier`, so nothing but this asserts it is substitutable.
    function test_selectorMatchesTheRealInterface() public pure {
        assertEq(MockVerifier.verify.selector, IVerifier.verify.selector);
    }

    function test_defaultsToSuccess() public view {
        (bool ok, uint8 code) = IVerifier(address(mock)).verify(_att(bytes32("a")), 0);
        assertTrue(ok);
        assertEq(code, VerifyCodes.R_OK);
    }

    function test_setResultRoundTrips() public {
        mock.setResult(false, VerifyCodes.R_BAD_SIGNATURE);
        (bool ok, uint8 code) = IVerifier(address(mock)).verify(_att(bytes32("a")), 0);
        assertFalse(ok);
        assertEq(code, VerifyCodes.R_BAD_SIGNATURE);
    }

    function test_perSourceOverrideBeatsTheDefault() public {
        mock.setResult(true, VerifyCodes.R_OK);
        mock.setResultFor(bytes32("b"), false, VerifyCodes.R_STALE);

        (bool okA,) = IVerifier(address(mock)).verify(_att(bytes32("a")), 0);
        assertTrue(okA);

        (bool okB, uint8 codeB) = IVerifier(address(mock)).verify(_att(bytes32("b")), 0);
        assertFalse(okB);
        assertEq(codeB, VerifyCodes.R_STALE);
    }

    /// @dev `MolphaLib` reaches the verifier through `STATICCALL`. If `verify` ever stopped being
    ///      `view`, every consumer using the mock would revert on a write in a static context.
    function test_verifyIsReachableThroughAStaticCall() public {
        mock.setResult(false, VerifyCodes.R_STALE);
        (bool success, bytes memory ret) =
            address(mock).staticcall(abi.encodeCall(IVerifier.verify, (_att(bytes32("a")), 0)));
        assertTrue(success, "verify must be view");
        (bool ok, uint8 code) = abi.decode(ret, (bool, uint8));
        assertFalse(ok);
        assertEq(code, VerifyCodes.R_STALE);
    }
}
