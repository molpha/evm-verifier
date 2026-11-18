// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";

import {IVerifier} from "../../src/interfaces/IVerifier.sol";
import {MolphaLib} from "../../src/consumer/MolphaLib.sol";
import {MolphaLibHarness} from "./MolphaLibHarness.sol";

/// @notice A policy's INCONCLUSIVE result is signed under I(S) = keccak256("MOLPHA_INCONCLUSIVE_V1" || S),
///         its value the reason (node-client docs/policy.md).
contract MolphaLibOutcomeTest is Test {
    bytes32 internal constant SOURCE = keccak256("MOLPHA_TEST_SOURCE");

    MolphaLibHarness internal harness;

    function setUp() public {
        harness = new MolphaLibHarness();
    }

    function _payload(bytes32 sourceId, bytes32 value) internal pure returns (IVerifier.AttestationPayload memory) {
        return IVerifier.AttestationPayload({
            value: value, sourceId: sourceId, registryVersion: 1, signaturesRequired: 3, timestamp: 1_795_000_000_000
        });
    }

    /// The node client's new/source/testdata/policy-vectors.json.
    function test_inconclusiveIdMatchesTheNodeVectors() public view {
        assertEq(harness.inconclusiveId(bytes32(0)), 0xbafadaff7889fa857773e328110d584e3d6bccb300737429d995d12e41325f0e);
        assertEq(
            harness.inconclusiveId(0xe371e37c37d592464b293ce89100c4c87ddcb667b901739c60827789b200b8af),
            0xf0f8a58c104feffc9dc7dbb32452ec9829d7d63ee8bcc1a41ba2c5784a29a9ce
        );
    }

    function test_readsTheSourceAsItsResult() public view {
        (bool inconclusive, uint8 reason) = harness.readOutcome(_payload(SOURCE, bytes32(uint256(42))), SOURCE);
        assertFalse(inconclusive);
        assertEq(reason, 0);
    }

    function test_readsIOfSAsAReason() public view {
        bytes32 i = harness.inconclusiveId(SOURCE);
        (bool inconclusive, uint8 reason) = harness.readOutcome(_payload(i, bytes32(uint256(0x11))), SOURCE);
        assertTrue(inconclusive);
        assertEq(reason, 0x11);
    }

    function test_refusesAnotherSource() public {
        bytes32 other = harness.inconclusiveId(harness.inconclusiveId(SOURCE));
        vm.expectRevert(abi.encodeWithSelector(MolphaLib.WrongSource.selector, SOURCE, other));
        harness.readOutcome(_payload(other, bytes32(uint256(1))), SOURCE);
    }

    function test_refusesAValueThatIsNotAReason() public {
        bytes32 i = harness.inconclusiveId(SOURCE);
        vm.expectRevert(abi.encodeWithSelector(MolphaLib.NotAReason.selector, bytes32(0)));
        harness.readOutcome(_payload(i, bytes32(0)), SOURCE);
        vm.expectRevert(abi.encodeWithSelector(MolphaLib.NotAReason.selector, bytes32(uint256(256))));
        harness.readOutcome(_payload(i, bytes32(uint256(256))), SOURCE);
    }

    function testFuzz_inconclusiveIdIsKeccakOfTagAndSource(bytes32 s) public view {
        assertEq(harness.inconclusiveId(s), keccak256(abi.encodePacked(bytes("MOLPHA_INCONCLUSIVE_V1"), s)));
        assertTrue(harness.inconclusiveId(s) != s);
    }
}
