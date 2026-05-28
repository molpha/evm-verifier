// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {Validator} from "../src/Validator.sol";
import {IValidatorStructs} from "../src/interfaces/IValidatorStructs.sol";
import {LibSecp256k1} from "../src/libs/LibSecp256k1.sol";
import {LibSchnorrTestSign} from "./libs/LibSchnorrTestSign.sol";

/// @title ValidatorFixtureJsonTest
/// @dev Golden compatibility test driven by `test/fixtures/fixture.json`.
///      PoP proofs are derived from fixture private keys (required for `addNode`);
///      verify inputs are taken verbatim from the fixture and not re-signed on-chain.
contract ValidatorFixtureJsonTest is Test {
    using stdJson for string;
    using LibSecp256k1 for LibSecp256k1.Point;

    bytes32 internal constant POP_DOMAIN = keccak256("MOLPHA_VALIDATOR_V1");
    string internal constant FIXTURE_PATH = "test/fixtures/fixture.json";

    function _pop(address validatorAddr, bytes memory compressed, uint256 sk)
        internal
        view
        returns (IValidatorStructs.SchnorrProof memory pop)
    {
        bytes32 digest = keccak256(abi.encodePacked(POP_DOMAIN, validatorAddr, compressed));
        LibSecp256k1.Point memory pk = LibSecp256k1.decompress(compressed);
        (bytes32 sig, address cmt) = LibSchnorrTestSign.sign(pk, sk, digest, 0);
        pop = IValidatorStructs.SchnorrProof({signature: sig, commitment: cmt});
    }

    function _loadDataUpdate(string memory json) internal view returns (IValidatorStructs.DataUpdate memory du) {
        du = IValidatorStructs.DataUpdate({
            jobId: json.readBytes32(".dataUpdate.jobId"),
            registryVersion: uint32(json.readUint(".dataUpdate.registryVersion")),
            signaturesRequired: uint32(json.readUint(".dataUpdate.signaturesRequired")),
            value: json.readBytes32(".dataUpdate.value"),
            canonicalTimestamp: uint64(json.readUint(".dataUpdate.canonicalTimestamp"))
        });
    }

    function _loadSchnorrSignature(string memory json)
        internal
        view
        returns (IValidatorStructs.SchnorrSignature memory sch)
    {
        sch = IValidatorStructs.SchnorrSignature({
            signature: json.readBytes32(".schnorrSignature.signature"),
            commitment: json.readAddress(".schnorrSignature.commitment"),
            signersBitmap: json.readUint(".schnorrSignature.signersBitmap")
        });
    }

    function test_verify_fixture_json() public {
        string memory json = vm.readFile(FIXTURE_PATH);

        uint256 registeredNodeCount = json.readUint(".registeredNodeCount");
        uint256 expectedRegistryVersion = json.readUint(".registryVersion");

        bytes[] memory pubkeys = json.readBytesArray(".nodePubkeys");
        string[] memory secretKeyStrings = json.readStringArray(".secretKeys");

        assertEq(pubkeys.length, registeredNodeCount, "nodePubkeys length");
        assertEq(secretKeyStrings.length, registeredNodeCount, "secretKeys length");

        Validator validator = new Validator();
        validator.initialize();

        for (uint256 i; i < pubkeys.length; ++i) {
            uint256 sk = vm.parseUint(secretKeyStrings[i]);
            validator.addNode(pubkeys[i], _pop(address(validator), pubkeys[i], sk));
        }

        assertEq(validator.getRegistryVersion(), expectedRegistryVersion, "registryVersion");
        assertEq(validator.getTotalNodes(), registeredNodeCount + 1, "blob length includes aggregate slot");

        IValidatorStructs.DataUpdate memory du = _loadDataUpdate(json);
        IValidatorStructs.SchnorrSignature memory sch = _loadSchnorrSignature(json);

        assertTrue(validator.verify(du, sch), "fixture.json verify must pass");
    }
}
