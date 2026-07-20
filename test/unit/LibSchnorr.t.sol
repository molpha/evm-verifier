// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";

import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";
import {LibSchnorr} from "../../src/libs/LibSchnorr.sol";
import {LibSchnorrTestSign} from "../libs/LibSchnorrTestSign.sol";

contract LibSchnorrHarness {
    function verify(LibSecp256k1.Point calldata pubkey, bytes32 message, bytes32 signature, address commitment)
        external
        pure
        returns (bool)
    {
        return LibSchnorr.verifySignature(pubkey, message, signature, commitment);
    }

    function verifyTrusted(LibSecp256k1.Point calldata pubkey, bytes32 message, bytes32 signature, address commitment)
        external
        pure
        returns (bool)
    {
        return LibSchnorr.verifySignatureTrusted(pubkey, message, signature, commitment);
    }
}

contract LibSchnorrTest is Test {
    LibSchnorrHarness internal harness = new LibSchnorrHarness();

    uint256 internal constant SECRET = 0xA11CE;
    bytes32 internal constant MESSAGE = keccak256("message");

    function _validSignature()
        internal
        pure
        returns (LibSecp256k1.Point memory pubkey, bytes32 signature, address commitment)
    {
        pubkey = LibSecp256k1.mulAffine(LibSecp256k1.G(), SECRET);
        (signature, commitment) = LibSchnorrTestSign.sign(pubkey, SECRET, MESSAGE, 0);
    }

    function test_verifySignature_acceptsValidSignature() public view {
        (LibSecp256k1.Point memory pubkey, bytes32 signature, address commitment) = _validSignature();

        assertTrue(harness.verify(pubkey, MESSAGE, signature, commitment));
        assertTrue(harness.verifyTrusted(pubkey, MESSAGE, signature, commitment));
    }

    function test_verifySignature_returnsFalseForTamperedMessage() public view {
        (LibSecp256k1.Point memory pubkey, bytes32 signature, address commitment) = _validSignature();

        assertFalse(harness.verify(pubkey, keccak256("other message"), signature, commitment));
        assertFalse(harness.verifyTrusted(pubkey, keccak256("other message"), signature, commitment));
    }

    function test_verifySignature_returnsFalseForZeroSignature() public view {
        (LibSecp256k1.Point memory pubkey,, address commitment) = _validSignature();

        assertFalse(harness.verify(pubkey, MESSAGE, 0, commitment));
    }

    function test_verifySignature_returnsFalseForZeroCommitment() public view {
        (LibSecp256k1.Point memory pubkey, bytes32 signature,) = _validSignature();

        assertFalse(harness.verify(pubkey, MESSAGE, signature, address(0)));
    }

    function test_verifySignature_returnsFalseForPointOutsideCurve() public view {
        LibSecp256k1.Point memory invalidPubkey = LibSecp256k1.Point({x: 1, y: 1});

        assertFalse(harness.verify(invalidPubkey, MESSAGE, bytes32(uint256(1)), address(1)));
    }

    function test_verifySignature_returnsFalseForOutOfRangeSignature() public view {
        (LibSecp256k1.Point memory pubkey,, address commitment) = _validSignature();

        assertFalse(harness.verify(pubkey, MESSAGE, bytes32(LibSecp256k1.Q()), commitment));
    }
}
