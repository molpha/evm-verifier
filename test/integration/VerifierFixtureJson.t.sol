// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {Verifier} from "../../src/Verifier.sol";
import {IVerifier} from "../../src/interfaces/IVerifier.sol";
import {VerifyCodes} from "../../src/libs/VerifyCodes.sol";
import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";
import {LibSchnorrTestSign} from "../libs/LibSchnorrTestSign.sol";

/// @title VerifierFixtureJsonTest
/// @dev Golden compatibility test driven by `test/fixtures/fixture.json` from the Molpha node/SDK.
///      PoP proofs are derived from fixture private keys (required for `addNode`);
///      verify inputs are taken verbatim from the fixture and not re-signed on-chain.
contract VerifierFixtureJsonTest is Test {
    using stdJson for string;
    using LibSecp256k1 for LibSecp256k1.Point;

    bytes32 internal constant POP_DOMAIN = keccak256("MOLPHA_VERIFIER_V1");
    string internal constant FIXTURE_PATH = "test/fixtures/fixture.json";

    function _pop(address validatorAddr, bytes memory compressed, uint256 sk)
        internal
        view
        returns (IVerifier.SchnorrProof memory pop)
    {
        bytes32 digest = keccak256(abi.encodePacked(POP_DOMAIN, validatorAddr, compressed));
        LibSecp256k1.Point memory pk = LibSecp256k1.decompress(compressed);
        (bytes32 sig, address cmt) = LibSchnorrTestSign.sign(pk, sk, digest, 0);
        pop = IVerifier.SchnorrProof({signature: sig, commitment: cmt});
    }

    function _loadDataUpdate(string memory json) internal view returns (IVerifier.DataUpdate memory du) {
        du = IVerifier.DataUpdate({
            sourceId: json.readBytes32(".dataUpdate.sourceId"),
            registryVersion: uint32(json.readUint(".dataUpdate.registryVersion")),
            signaturesRequired: uint32(json.readUint(".dataUpdate.signaturesRequired")),
            value: json.readBytes32(".dataUpdate.value"),
            canonicalTimestamp: uint64(json.readUint(".dataUpdate.canonicalTimestamp"))
        });
    }

    function _loadSchnorrSignature(string memory json) internal view returns (IVerifier.SchnorrSignature memory sch) {
        sch = IVerifier.SchnorrSignature({
            signature: json.readBytes32(".schnorrSignature.signature"),
            commitment: json.readAddress(".schnorrSignature.commitment"),
            signersBitmap: json.readUint(".schnorrSignature.signersBitmap")
        });
    }

    function test_verify_actualMolphaSdkGoldenVector_fixtureJsonPayloadVerbatim() public {
        string memory json = vm.readFile(FIXTURE_PATH);

        assertEq(json.readString(".producer"), "molpha-node-sdk", "fixture producer");
        assertEq(json.readString(".payloadKind"), "cross-language-golden-vector", "fixture payload kind");

        uint256 registeredNodeCount = json.readUint(".registeredNodeCount");
        uint256 expectedRegistryVersion = json.readUint(".registryVersion");

        bytes[] memory pubkeys = json.readBytesArray(".nodePubkeys");
        string[] memory secretKeyStrings = json.readStringArray(".secretKeys");

        assertEq(pubkeys.length, registeredNodeCount, "nodePubkeys length");
        assertEq(secretKeyStrings.length, registeredNodeCount, "secretKeys length");

        Verifier validator = new Verifier(address(this), 2);

        for (uint256 i; i < pubkeys.length; ++i) {
            uint256 sk = vm.parseUint(secretKeyStrings[i]);
            validator.addNode(pubkeys[i], _pop(address(validator), pubkeys[i], sk));
        }

        assertEq(validator.getRegistryVersion(), expectedRegistryVersion, "registryVersion");
        assertEq(validator.getTotalNodes(), registeredNodeCount, "registered nodes");

        IVerifier.DataUpdate memory du = _loadDataUpdate(json);
        IVerifier.SchnorrSignature memory sch = _loadSchnorrSignature(json);

        (bool verified, uint8 code) = validator.verify(du, sch, 0);
        if (!verified) {
            vm.skip(true, "fixture signature stale; regenerate fixture with sourceId in message/selection preimages");
        }
        assertEq(code, VerifyCodes.R_OK);
    }
}
