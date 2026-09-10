// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";

import {StructuredPayload} from "../../examples/StructuredPayload.sol";
import {IVerifier} from "@molpha/evm-verifier/interfaces/IVerifier.sol";
import {MolphaLib} from "@molpha/evm-verifier/consumer/MolphaLib.sol";
import {MolphaTestSigner} from "@molpha/evm-verifier/test-utils/MolphaTestSigner.sol";

contract StructuredPayloadTest is Test {
    bytes32 internal constant SOURCE = keccak256("MOLPHA_STRUCTURED_SOURCE");
    uint8 internal constant MIN_SIGS = 5;

    MolphaTestSigner internal signer;
    StructuredPayload internal sink;

    function setUp() public {
        vm.warp(1_700_000_000);
        signer = new MolphaTestSigner(2);
        signer.registerNodes(8);
        sink = new StructuredPayload(IVerifier(address(signer.verifier())), SOURCE, MIN_SIGS, MolphaLib.NO_MAX_AGE);
    }

    function _fields(uint256 amount, bytes32 label, string memory note) internal pure returns (bytes memory) {
        return abi.encode(amount, label, note);
    }

    function test_ingestsAndDecodesTheTuple() public {
        bytes memory fields = _fields(1234, bytes32("gold"), "spot close");
        sink.ingest(signer.attestFields(SOURCE, fields, MIN_SIGS, uint64(block.timestamp)), fields);

        (uint256 amount, bytes32 label, string memory note) = sink.readings(0);
        assertEq(amount, 1234);
        assertEq(label, bytes32("gold"));
        assertEq(note, "spot close");
        assertEq(sink.readingCount(), 1);
    }

    function test_mismatchedFieldsAreRejected() public {
        bytes memory signed = _fields(1234, bytes32("gold"), "spot close");
        bytes memory swapped = _fields(9999, bytes32("gold"), "spot close");
        IVerifier.Attestation memory att = signer.attestFields(SOURCE, signed, MIN_SIGS, uint64(block.timestamp));

        vm.expectPartialRevert(MolphaLib.PayloadMismatch.selector);
        sink.ingest(att, swapped);
    }

    function test_consumingTheSameAttestationTwiceIsRejected() public {
        bytes memory fields = _fields(1, bytes32("x"), "n");
        IVerifier.Attestation memory att = signer.attestFields(SOURCE, fields, MIN_SIGS, uint64(block.timestamp));
        sink.ingest(att, fields);

        vm.expectPartialRevert(MolphaLib.AlreadyConsumed.selector);
        sink.ingest(att, fields);
    }

    function test_outOfOrderIngestIsAllowed() public {
        uint64 t0 = uint64(block.timestamp);
        bytes memory a = _fields(1, bytes32("a"), "first");
        bytes memory b = _fields(2, bytes32("b"), "second");

        sink.ingest(signer.attestFields(SOURCE, a, MIN_SIGS, t0 + 500), a);
        sink.ingest(signer.attestFields(SOURCE, b, MIN_SIGS, t0 + 100), b);
        assertEq(sink.readingCount(), 2, "Consumed accepts any order, unlike Latest");
    }

    /// @dev The grace-window property, end to end: the same observation re-attested under a NEWER
    ///      registry version is one logical update, and the guard must reject the second.
    function test_sameObservationUnderANewRegistryVersionIsAlreadyConsumed() public {
        uint64 ts = uint64(block.timestamp);
        bytes memory fields = _fields(7, bytes32("v"), "grace");

        IVerifier.Attestation memory first = signer.attestFields(SOURCE, fields, MIN_SIGS, ts);
        sink.ingest(first, fields);

        // Publish a new registry version, then re-attest the identical observation under it.
        signer.registerNodes(1);
        IVerifier.Attestation memory second = signer.attestFields(SOURCE, fields, MIN_SIGS, ts);
        assertTrue(second.payload.registryVersion > first.payload.registryVersion, "version must advance");

        vm.expectPartialRevert(MolphaLib.AlreadyConsumed.selector);
        sink.ingest(second, fields);
    }
}
