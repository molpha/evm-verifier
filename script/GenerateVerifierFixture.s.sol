// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.31;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IVerifier} from "../src/interfaces/IVerifier.sol";
import {LibSecp256k1} from "../src/libs/LibSecp256k1.sol";
import {MolphaSigLib} from "../src/test-utils/MolphaSigLib.sol";

/// @notice Refreshes the signature fields in the node/SDK compatibility fixture after an
///         intentional signed-preimage change. Registry keys and payload inputs stay fixed.
contract GenerateVerifierFixture is Script {
    using stdJson for string;

    string internal constant FIXTURE = "test/fixtures/fixture.json";
    uint256 internal constant REDUNDANCY_BUFFER = 2;
    uint256 internal constant SIGNER_COUNT = 7;

    function run() external {
        string memory json = vm.readFile(FIXTURE);
        uint256 nodeCount = json.readUint(".registeredNodeCount");
        uint256[] memory secrets = new uint256[](nodeCount);
        LibSecp256k1.Point[] memory pubkeys = new LibSecp256k1.Point[](nodeCount);

        for (uint256 i; i < nodeCount; ++i) {
            secrets[i] = json.readUint(string.concat(".secretKeys[", vm.toString(i), "]"));
            pubkeys[i] = LibSecp256k1.mulAffine(LibSecp256k1.G(), secrets[i]);
        }

        IVerifier.AttestationPayload memory payload = IVerifier.AttestationPayload({
            value: json.readBytes32(".dataUpdate.value"),
            sourceId: json.readBytes32(".dataUpdate.sourceId"),
            registryVersion: uint32(json.readUint(".dataUpdate.registryVersion")),
            signaturesRequired: uint8(json.readUint(".dataUpdate.signaturesRequired")),
            canonicalTimestamp: uint64(json.readUint(".dataUpdate.canonicalTimestamp"))
        });
        IVerifier.Attestation memory attestation =
            MolphaSigLib.buildAttestation(secrets, pubkeys, payload, REDUNDANCY_BUFFER, SIGNER_COUNT);

        require(
            attestation.signature.signersBitmap == json.readUint(".schnorrSignature.signersBitmap"),
            "selection changed; review the human-readable node indexes"
        );

        vm.writeJson(
            _quoted(vm.toString(MolphaSigLib.message(payload, attestation.signature.signersBitmap))),
            FIXTURE,
            ".messageHash"
        );
        vm.writeJson(_quoted(vm.toString(attestation.signature.signature)), FIXTURE, ".schnorrSignature.signature");
        vm.writeJson(_quoted(vm.toString(attestation.signature.commitment)), FIXTURE, ".schnorrSignature.commitment");
    }

    function _quoted(string memory value) private pure returns (string memory) {
        return string.concat('"', value, '"');
    }
}
