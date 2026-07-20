// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";

import {Verifier} from "../src/Verifier.sol";
import {IVerifier} from "../src/interfaces/IVerifier.sol";
import {LibSecp256k1} from "../src/libs/LibSecp256k1.sol";
import {LibSchnorrTestSign} from "./libs/LibSchnorrTestSign.sol";

/// @title VerifierCompatFixtureTest
/// @dev Golden compatibility test: register nodes and verify using only the external fixture payload.
///      PoP proofs are derived from fixture private keys (required for `addNode`); verify inputs are not re-signed.
contract VerifierCompatFixtureTest is Test {
    using LibSecp256k1 for LibSecp256k1.Point;

    bytes32 internal constant POP_DOMAIN = keccak256("MOLPHA_VALIDATOR_V1");

    uint256 internal constant REGISTERED_NODE_COUNT = 8;
    uint256 internal constant FIXTURE_REGISTRY_VERSION = 8;

    bytes32 internal constant FIXTURE_JOB_ID = 0xe1dd7a3c71d4405dc3c7c172413fa866e19584f5f1259b6c508b08541238cc8b;

    bytes32 internal constant FIXTURE_VALUE = 0x14e9eed69e93058c250c39f1adc7ef572441f9fa2ff89d314b56e77b6aa648de;

    uint64 internal constant FIXTURE_CANONICAL_TIMESTAMP = 1_708_783_016;

    bytes32 internal constant FIXTURE_SCHNORR_SIGNATURE =
        0x2f23ba52761a50b5247e3f76f695dff8a9723bf7da8305c13102f72abd08d44c;

    address internal constant FIXTURE_SCHNORR_COMMITMENT = 0x77876a88E5552f1Ea7Bea643ac009611EF8d28df;

    uint256 internal constant FIXTURE_SIGNERS_BITMAP = 255;

    function _fixtureCompressedPubkeys() internal pure returns (bytes[8] memory keys) {
        keys[0] = hex"0262fb49c25e1ee5c2d3c007852bba4875912b5c2db05fa8b5cfdb066058261519";
        keys[1] = hex"03a5ecc1cd542aa9acddd05fb1e9fc00b44fb2a2339e946ef7904aa946bec877aa";
        keys[2] = hex"022c45685bff1c919c30fe2d3b88bab902a7a3da1882aa9a2f8edf7edc3157e48c";
        keys[3] = hex"027ca6e5898ca8b09cd128e86b8cbeff732f0b821dcf76ae5e1948a67cdf31de01";
        keys[4] = hex"03b14eb49737c370fa5a3f59a63ea7f0bf1484dc3d440b0264a819bd4a0722b4b5";
        keys[5] = hex"03d092409fab746fde5e4d2f56e147147247a36aa38423b7f2127ab86b972f7bfc";
        keys[6] = hex"0301e5c42a082c9ded026ae2b69c753ac57b81bb3a0dc5d8fcbc662dacc0f42443";
        keys[7] = hex"03aafc0c2190bd1bf18cdee97e2c11d8cdbc09d5fb2b8916b1105d75e7ab07d943";
    }

    function _fixtureNodePrivkeys() internal pure returns (uint256[8] memory sks) {
        sks[0] = 0xe94009abe8d8d6d04422b209698ac53a9a86b9db38b024b4b45a16fe7a182e8a;
        sks[1] = 0x6611e8f29a26584de5158c4c403e5b3bbfc8672025fe85040846328f17f0c1c;
        sks[2] = 0xb52e550a6d99d6ffc1e4dde87a6632ae61e371bbd9892ce8a26881c31e42ac9d;
        sks[3] = 0x343ef3e2d033b55df2b4cc1f2212b6d44ce6fb5de9d8b60097ddb758b044d8cd;
        sks[4] = 0x41df793964c799f122401cb7ef37462315c71fe3370a8637c01f17b09642ebe6;
        sks[5] = 0x35de355094f9248432a36f3102ae7f18467a7772845cfbe896423be12d24b9af;
        sks[6] = 0x778424aea3e58ff040f6dfe1c47d192e88895bdec5f6082934aa3261b96045d6;
        sks[7] = 0x5acb590b45389c8ddd1c40861a6ddc24f52c267859d2e3f6de2d44b95b209e7a;
    }

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

    function _fixtureDataUpdate() internal pure returns (IVerifier.DataUpdate memory du) {
        du = IVerifier.DataUpdate({
            feedId: FIXTURE_JOB_ID,
            registryVersion: uint32(FIXTURE_REGISTRY_VERSION),
            signaturesRequired: 8,
            value: FIXTURE_VALUE,
            canonicalTimestamp: FIXTURE_CANONICAL_TIMESTAMP
        });
    }

    function _fixtureSchnorrSignature() internal pure returns (IVerifier.SchnorrSignature memory sch) {
        sch = IVerifier.SchnorrSignature({
            signature: FIXTURE_SCHNORR_SIGNATURE,
            commitment: FIXTURE_SCHNORR_COMMITMENT,
            signersBitmap: FIXTURE_SIGNERS_BITMAP
        });
    }

    function test_verify_compat_external_fixture_8nodes() public {
        Verifier validator = new Verifier(address(this), 2);

        bytes[8] memory pubkeys = _fixtureCompressedPubkeys();
        uint256[8] memory privkeys = _fixtureNodePrivkeys();

        for (uint256 i; i < REGISTERED_NODE_COUNT; ++i) {
            validator.addNode(pubkeys[i], _pop(address(validator), pubkeys[i], privkeys[i]));
        }

        assertEq(validator.getRegistryVersion(), FIXTURE_REGISTRY_VERSION, "registryVersion");
        assertEq(validator.getTotalNodes(), REGISTERED_NODE_COUNT, "registered nodes");

        IVerifier.DataUpdate memory du = _fixtureDataUpdate();
        IVerifier.SchnorrSignature memory sch = _fixtureSchnorrSignature();

        bool verified = validator.verify(du, sch);
        assertTrue(verified, "external fixture verify must pass");
    }
}
