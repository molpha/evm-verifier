// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IVerifier} from "../../src/interfaces/IVerifier.sol";
import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";
import {MolphaLib} from "../../src/consumer/MolphaLib.sol";
import {MolphaSigLib} from "../../src/test-utils/MolphaSigLib.sol";
import {Verifier} from "../../src/Verifier.sol";
import {MolphaLibHarness} from "../consumer/MolphaLibHarness.sol";

/// @title AttestationFixtureJsonTest
/// @dev Cross-VM parity vector for the consumer SDK. `messageHash` and `replayKey` are the anchors
///      the Cairo and Rust verifiers must reproduce for identical inputs. The attestations are
///      taken verbatim from the fixture and never re-signed here; only the PoP proofs needed by
///      `addNode` are derived on the fly.
///
///      Regenerate with `forge script script/GenerateAttestationFixture.s.sol` — and only when the
///      wire format changes on purpose. A failure here means the format moved.
contract AttestationFixtureJsonTest is Test {
    using stdJson for string;

    string internal constant FIXTURE = "test/fixtures/attestation.json";

    Verifier internal verifier;
    MolphaLibHarness internal harness;
    string internal json;

    function setUp() public {
        json = vm.readFile(FIXTURE);
        harness = new MolphaLibHarness();

        uint256 nodeCount = json.readUint(".registeredNodeCount");
        uint256 buffer = json.readUint(".redundancyBuffer");
        vm.warp(json.readUint(".cases[0].attestation.payload.canonicalTimestamp"));

        verifier = new Verifier(address(this), buffer);
        string memory keys = vm.readFile(json.readString(".keysFrom"));
        for (uint256 i; i < nodeCount; ++i) {
            uint256 sk = keys.readUint(string.concat(".secretKeys[", vm.toString(i), "]"));
            bytes memory compressed = LibSecp256k1.compress(LibSecp256k1.mulAffine(LibSecp256k1.G(), sk));
            verifier.addNode(compressed, MolphaSigLib.proofOfPossession(address(verifier), compressed, sk));
        }
        assertEq(verifier.getRegistryVersion(), json.readUint(".registryVersion"), "registryVersion");
    }

    function test_kindAWordVector() public view {
        _assertCase(0);
        // The word decodes as the signed value the fixture records.
        assertEq(
            harness.asInt256(json.readBytes32(".cases[0].attestation.payload.value")),
            vm.parseInt(json.readString(".cases[0].expected.asInt256"))
        );
    }

    function test_kindBTupleVector() public view {
        _assertCase(1);

        bytes memory encodedFields = json.readBytes(".cases[1].encodedFields");
        IVerifier.Attestation memory att = _attestation(1);
        assertEq(keccak256(encodedFields), att.payload.value, "digest binding");

        (bool ok, uint8 code) = harness.isValidFields(IVerifier(address(verifier)), att, _policy(1), encodedFields);
        assertTrue(ok, "kind B libOk");
        assertEq(code, uint8(json.readUint(".cases[1].expected.libCode")), "kind B libCode");

        (uint256 amount, bytes32 label, string memory note) = abi.decode(encodedFields, (uint256, bytes32, string));
        assertEq(amount, 42);
        assertEq(label, bytes32("molpha"));
        assertEq(note, "cross-vm");
    }

    /// @dev Shared by both cases: verifier result, library result, and the two parity anchors.
    function _assertCase(uint256 i) private view {
        string memory p = string.concat(".cases[", vm.toString(i), "].");
        IVerifier.Attestation memory att = _attestation(i);

        (bool ok, uint8 code) = verifier.verify(att, 0);
        assertEq(ok, json.readBool(string.concat(p, "expected.verifyOk")), "verifyOk");
        assertEq(code, uint8(json.readUint(string.concat(p, "expected.verifyCode"))), "verifyCode");

        (bool libOk, uint8 libCode) = harness.isValid(IVerifier(address(verifier)), att, _policy(i));
        assertEq(libOk, json.readBool(string.concat(p, "expected.libOk")), "libOk");
        assertEq(libCode, uint8(json.readUint(string.concat(p, "expected.libCode"))), "libCode");

        assertEq(
            MolphaSigLib.message(att.payload, att.signature.signersBitmap),
            json.readBytes32(string.concat(p, "expected.messageHash")),
            "messageHash parity anchor"
        );
        assertEq(
            harness.replayKey(att.payload),
            json.readBytes32(string.concat(p, "expected.replayKey")),
            "replayKey parity anchor"
        );
    }

    function _attestation(uint256 i) private view returns (IVerifier.Attestation memory) {
        string memory p = string.concat(".cases[", vm.toString(i), "].attestation.");
        return IVerifier.Attestation({
            payload: IVerifier.AttestationPayload({
                value: json.readBytes32(string.concat(p, "payload.value")),
                sourceId: json.readBytes32(string.concat(p, "payload.sourceId")),
                registryVersion: uint32(json.readUint(string.concat(p, "payload.registryVersion"))),
                signaturesRequired: uint8(json.readUint(string.concat(p, "payload.signaturesRequired"))),
                canonicalTimestamp: uint64(json.readUint(string.concat(p, "payload.canonicalTimestamp")))
            }),
            signature: IVerifier.SchnorrSignature({
                signature: json.readBytes32(string.concat(p, "signature.signature")),
                commitment: json.readAddress(string.concat(p, "signature.commitment")),
                signersBitmap: json.readUint(string.concat(p, "signature.signersBitmap"))
            })
        });
    }

    function _policy(uint256 i) private view returns (MolphaLib.Policy memory) {
        string memory p = string.concat(".cases[", vm.toString(i), "].policy.");
        return MolphaLib.Policy({
            sourceId: json.readBytes32(string.concat(p, "sourceId")),
            minSignatures: uint32(json.readUint(string.concat(p, "minSignatures"))),
            maxAge: uint64(json.readUint(string.concat(p, "maxAge")))
        });
    }
}
