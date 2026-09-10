// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.31;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IVerifier} from "../src/interfaces/IVerifier.sol";
import {LibSecp256k1} from "../src/libs/LibSecp256k1.sol";
import {MolphaLib} from "../src/consumer/MolphaLib.sol";
import {MolphaSigLib} from "../src/test-utils/MolphaSigLib.sol";
import {Verifier} from "../src/Verifier.sol";

/// @notice Regenerates `test/fixtures/attestation.json`, the consumer-SDK cross-VM parity vector.
/// @dev Run with `forge script script/GenerateAttestationFixture.s.sol`. Reuses the 12 keys from
///      `fixture.json` so both fixtures describe one registry and the Cairo/Rust repos can share
///      setup code. Regenerate only when the wire format or the fixture inputs change on purpose;
///      `AttestationFixtureJson.t.sol` is what proves the committed file still holds.
contract GenerateAttestationFixture is Script {
    using stdJson for string;
    using LibSecp256k1 for LibSecp256k1.Point;

    uint256 internal constant NODE_COUNT = 12;
    uint256 internal constant REDUNDANCY_BUFFER = 2;
    uint8 internal constant SIGNATURES_REQUIRED = 5;
    uint64 internal constant CANONICAL_TIMESTAMP = 1_700_000_000;
    bytes32 internal constant SOURCE_ID = keccak256("MOLPHA_CONSUMER_SDK_SOURCE");

    uint256[] internal secrets;
    LibSecp256k1.Point[] internal pubkeys;

    function run() external {
        vm.warp(CANONICAL_TIMESTAMP);
        string memory src = vm.readFile("test/fixtures/fixture.json");
        // A script contract's own address is ephemeral, so the registry owner is an explicit
        // pranked EOA rather than `address(this)`.
        address admin = address(uint160(uint256(keccak256("MOLPHA_FIXTURE_ADMIN"))));
        Verifier verifier = new Verifier(admin, REDUNDANCY_BUFFER);
        vm.startPrank(admin);

        for (uint256 i; i < NODE_COUNT; ++i) {
            uint256 sk = src.readUint(string.concat(".secretKeys[", vm.toString(i), "]"));
            LibSecp256k1.Point memory pk = LibSecp256k1.mulAffine(LibSecp256k1.G(), sk);
            bytes memory compressed = LibSecp256k1.compress(pk);
            secrets.push(sk);
            pubkeys.push(pk);
            verifier.addNode(compressed, MolphaSigLib.proofOfPossession(address(verifier), compressed, sk));
        }

        vm.stopPrank();

        uint32 registryVersion = uint32(verifier.getRegistryVersion());

        // Kind A: the result word itself, a negative int256 so sign extension is exercised.
        bytes32 wordValue = bytes32(uint256(int256(-1234)));
        IVerifier.Attestation memory kindA = _build(wordValue, registryVersion);

        // Kind B: keccak256 over an ABI-encoded three-field tuple.
        // casting to 'bytes32' is safe because "molpha" is a 6-byte literal, well under 32.
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory encodedFields = abi.encode(uint256(42), bytes32("molpha"), "cross-vm");
        IVerifier.Attestation memory kindB = _build(keccak256(encodedFields), registryVersion);

        (bool okA, uint8 codeA) = verifier.verify(kindA, 0);
        (bool okB, uint8 codeB) = verifier.verify(kindB, 0);
        require(okA && codeA == 0 && okB && codeB == 0, "fixture must verify");

        vm.writeFile(
            "test/fixtures/attestation.json",
            string.concat(
                _header(registryVersion),
                _case("kindA-int256", "A", kindA, "", '"asInt256": "-1234"'),
                ",\n",
                _case("kindB-tuple", "B", kindB, encodedFields, '"tuple": [42, "molpha", "cross-vm"]'),
                "\n  ]\n}\n"
            )
        );
    }

    /// @dev Split out of `run` so each frame stays shallow enough for `--ir-minimum`, which the
    ///      repo's `forge coverage` workflow uses.
    function _header(uint32 registryVersion) private pure returns (string memory) {
        return string.concat(
            "{\n",
            '  "producer": "molpha-evm-verifier",\n',
            '  "payloadKind": "consumer-sdk-attestation-vector",\n',
            '  "version": 1,\n',
            '  "note": "Shares the 12 keys of fixture.json. messageHash and replayKey are the cross-VM parity anchors.",\n',
            '  "registeredNodeCount": ',
            vm.toString(NODE_COUNT),
            ",\n",
            '  "redundancyBuffer": ',
            vm.toString(REDUNDANCY_BUFFER),
            ",\n",
            '  "registryVersion": ',
            vm.toString(uint256(registryVersion)),
            ",\n",
            '  "keysFrom": "test/fixtures/fixture.json",\n',
            '  "cases": [\n'
        );
    }

    function _build(bytes32 value, uint32 registryVersion) private view returns (IVerifier.Attestation memory) {
        IVerifier.AttestationPayload memory payload = IVerifier.AttestationPayload({
            value: value,
            sourceId: SOURCE_ID,
            registryVersion: registryVersion,
            signaturesRequired: SIGNATURES_REQUIRED,
            canonicalTimestamp: CANONICAL_TIMESTAMP
        });
        return MolphaSigLib.buildAttestation(secrets, pubkeys, payload, REDUNDANCY_BUFFER, SIGNATURES_REQUIRED);
    }

    function _case(
        string memory name,
        string memory kind,
        IVerifier.Attestation memory att,
        bytes memory encodedFields,
        string memory extra
    ) private pure returns (string memory) {
        return string.concat(
            "    {\n",
            '      "name": "',
            name,
            '",\n      "kind": "',
            kind,
            '",\n',
            bytes(encodedFields).length == 0
                ? ""
                : string.concat('      "encodedFields": "', vm.toString(encodedFields), '",\n'),
            '      "attestation": {\n',
            _payloadJson(att.payload),
            _signatureJson(att.signature),
            "      },\n",
            _policyJson(att.payload.sourceId),
            _expectedJson(att, extra),
            "    }"
        );
    }

    function _payloadJson(IVerifier.AttestationPayload memory p) private pure returns (string memory) {
        return string.concat(
            '        "payload": {\n          "value": "',
            vm.toString(p.value),
            '",\n          "sourceId": "',
            vm.toString(p.sourceId),
            '",\n          "registryVersion": ',
            vm.toString(uint256(p.registryVersion)),
            ',\n          "signaturesRequired": ',
            vm.toString(uint256(p.signaturesRequired)),
            ',\n          "canonicalTimestamp": ',
            vm.toString(uint256(p.canonicalTimestamp)),
            "\n        },\n"
        );
    }

    function _signatureJson(IVerifier.SchnorrSignature memory sig) private pure returns (string memory) {
        return string.concat(
            '        "signature": {\n          "signature": "',
            vm.toString(sig.signature),
            '",\n          "commitment": "',
            vm.toString(sig.commitment),
            '",\n          "signersBitmap": ',
            vm.toString(sig.signersBitmap),
            "\n        }\n"
        );
    }

    function _policyJson(bytes32 sourceId) private pure returns (string memory) {
        return string.concat(
            '      "policy": { "sourceId": "',
            vm.toString(sourceId),
            '", "minSignatures": ',
            vm.toString(uint256(SIGNATURES_REQUIRED)),
            ', "maxAge": 0 },\n'
        );
    }

    function _expectedJson(IVerifier.Attestation memory att, string memory extra) private pure returns (string memory) {
        return string.concat(
            '      "expected": {\n',
            '        "verifyOk": true,\n        "verifyCode": 0,\n        "libOk": true,\n        "libCode": 0,\n',
            '        "messageHash": "',
            vm.toString(MolphaSigLib.message(att.payload, att.signature.signersBitmap)),
            '",\n        "replayKey": "',
            vm.toString(keccak256(abi.encodePacked(att.payload.sourceId, att.payload.canonicalTimestamp))),
            '",\n        ',
            extra,
            "\n      }\n"
        );
    }
}
