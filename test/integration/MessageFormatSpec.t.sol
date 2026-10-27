// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";

import {IVerifier} from "../../src/interfaces/IVerifier.sol";
import {KeysCommitmentLib} from "../../src/libs/KeysCommitmentLib.sol";
import {VerifierLib} from "../../src/libs/VerifierLib.sol";
import {Verifier} from "../../src/Verifier.sol";

/// @dev `constructMessage` takes calldata, so it needs an external frame.
contract MessagePreimageHarness {
    function message(IVerifier.AttestationPayload calldata dataUpdate, uint256 signersBitmap)
        external
        pure
        returns (bytes32)
    {
        return VerifierLib.constructMessage(dataUpdate, signersBitmap);
    }
}

/// @title MessageFormatSpec
/// @notice Pins the wire format documented in `docs/message-format.md` to literal digests.
/// @dev The golden-vector fixtures in this directory currently self-skip, and every other test
///      builds its preimages with a helper that mirrors the contract — so a matching change on both
///      sides would go unnoticed. The expected values below were computed outside Solidity from the
///      byte layout in the spec, which makes them an independent check on the encoding and a
///      concrete target for the off-chain signer.
contract MessageFormatSpecTest is Test {
    MessagePreimageHarness internal harness = new MessagePreimageHarness();

    // Fixed vector; the digests below are only valid for exactly these values.
    bytes32 internal constant SOURCE_ID = bytes32(uint256(1));
    uint32 internal constant REGISTRY_VERSION = 7;
    uint8 internal constant SIGNATURES_REQUIRED = 3;
    uint256 internal constant SIGNERS_BITMAP = 0x83; // nodes 0, 1 and 7, per the spec's example
    bytes32 internal constant VALUE = bytes32(uint256(0xdeadbeef));
    uint64 internal constant TIMESTAMP = 1_699_965_440_000; // unix ms; second 0x65536a00

    bytes32 internal constant EXPECTED_MESSAGE = 0xd4b03dd5a71d9afbac41567f7409f2723943191b30243332b56143320d749838;

    function _update() internal pure returns (IVerifier.AttestationPayload memory) {
        return IVerifier.AttestationPayload({
            sourceId: SOURCE_ID,
            registryVersion: REGISTRY_VERSION,
            signaturesRequired: SIGNATURES_REQUIRED,
            value: VALUE,
            timestamp: TIMESTAMP
        });
    }

    // ---------------------------------------------------------------------
    // Domain separators
    // ---------------------------------------------------------------------

    /// @dev Every domain string is part of the cross-chain and cross-language contract; a typo
    ///      would silently fork the protocol from the off-chain signer.
    function test_domainSeparators_matchTheirDocumentedStrings() public pure {
        assertEq(
            keccak256("MOLPHA_MESSAGE_V1"),
            0xa75523a2ab7b718d9cffd2fa97ed069fc12184eabee7d507854d0922f70e7fe7,
            "message prefix"
        );
        assertEq(
            keccak256("MOLPHA_VERIFIER_V1"),
            0x789b999d1d38ea94308dd6904bfa70cf9ee14dd2b978fb6d2c894c9c84150a04,
            "proof-of-possession domain"
        );
        assertEq(
            keccak256("MOLPHA_REGISTRY_TRANSITION_V2"),
            0x73a75293a353d308c5f616f71fce7ce2fe4a81098524997783b7e13a5c359fbb,
            "registry transition domain"
        );
        assertEq(
            keccak256("MOLPHA_REGISTRY_GENESIS_V1"),
            0xc1d8611ff8d024c57f3f1797affc12d755596e27b3096334f6f8efb244b1afbf,
            "registry genesis root"
        );
    }

    function test_genesisRootIsTheDocumentedConstant() public {
        Verifier fresh = new Verifier(address(this));
        assertEq(fresh.getRegistryRoot(0), 0xc1d8611ff8d024c57f3f1797affc12d755596e27b3096334f6f8efb244b1afbf);
    }

    function test_emptyKeysCommitmentIsTheHashOfTheEmptyString() public pure {
        assertEq(
            KeysCommitmentLib.emptyCommitment(), 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470
        );
    }

    // ---------------------------------------------------------------------
    // Signed message
    // ---------------------------------------------------------------------

    function test_constructMessage_matchesTheSpecifiedDigest() public view {
        assertEq(harness.message(_update(), SIGNERS_BITMAP), EXPECTED_MESSAGE);
    }

    /// @dev Field widths are the part cross-language implementations get wrong most easily:
    ///      `abi.encodePacked` writes `registryVersion` as 4 bytes, `signaturesRequired` as one,
    ///      and `timestamp` as 8, not as 32-byte words.
    function test_constructMessage_isSensitiveToFieldWidths() public view {
        bytes32 actual = harness.message(_update(), SIGNERS_BITMAP);

        bytes32 wordWidthVersion = keccak256(
            abi.encodePacked(
                keccak256("MOLPHA_MESSAGE_V1"),
                VALUE,
                SOURCE_ID,
                uint256(REGISTRY_VERSION),
                SIGNATURES_REQUIRED,
                TIMESTAMP,
                SIGNERS_BITMAP
            )
        );
        assertTrue(actual != wordWidthVersion, "registryVersion must be encoded as uint32");

        bytes32 wordWidthQuorum = keccak256(
            abi.encodePacked(
                keccak256("MOLPHA_MESSAGE_V1"),
                VALUE,
                SOURCE_ID,
                REGISTRY_VERSION,
                uint32(SIGNATURES_REQUIRED),
                TIMESTAMP,
                SIGNERS_BITMAP
            )
        );
        assertTrue(actual != wordWidthQuorum, "signaturesRequired must be encoded as uint8");

        bytes32 wordWidthTimestamp = keccak256(
            abi.encodePacked(
                keccak256("MOLPHA_MESSAGE_V1"),
                VALUE,
                SOURCE_ID,
                REGISTRY_VERSION,
                SIGNATURES_REQUIRED,
                uint256(TIMESTAMP),
                SIGNERS_BITMAP
            )
        );
        assertTrue(actual != wordWidthTimestamp, "timestamp must be encoded as uint64");
    }

    /// @dev Byte-for-byte fixture shared with `molpha-verifier/tests/fixtures/mod.rs` and the SDK.
    function test_constructMessage_matchesRustAndSdkSharedVector() public view {
        IVerifier.AttestationPayload memory payload = IVerifier.AttestationPayload({
            value: 0x12cd90a4cd4351a26f2bd02583d791ae1b1a3285853a3315e718db8d7b85a62d,
            sourceId: 0x41b87cd1b00231a5caebdfbc3e352d92bb0ec116335cc3544278a4bac95071a7,
            registryVersion: 12,
            signaturesRequired: 5,
            timestamp: 1_705_257_421_000
        });
        assertEq(harness.message(payload, 0x0fa8), 0xe1bedfeec7c869576b3a5048215e2be458a02f73ad3736d34d091c363b9dd54f);
    }

    /// @dev Every signed field has to reach the digest, or it could be swapped after signing.
    function test_constructMessage_dependsOnEverySignedField() public view {
        bytes32 base = harness.message(_update(), SIGNERS_BITMAP);

        IVerifier.AttestationPayload memory update = _update();
        update.sourceId = bytes32(uint256(2));
        assertTrue(harness.message(update, SIGNERS_BITMAP) != base, "sourceId");

        update = _update();
        update.registryVersion = REGISTRY_VERSION + 1;
        assertTrue(harness.message(update, SIGNERS_BITMAP) != base, "registryVersion");

        update = _update();
        update.signaturesRequired = SIGNATURES_REQUIRED + 1;
        assertTrue(harness.message(update, SIGNERS_BITMAP) != base, "signaturesRequired");

        update = _update();
        update.value = bytes32(uint256(0xfeed));
        assertTrue(harness.message(update, SIGNERS_BITMAP) != base, "value");

        update = _update();
        update.timestamp = TIMESTAMP + 1;
        assertTrue(harness.message(update, SIGNERS_BITMAP) != base, "timestamp");

        assertTrue(harness.message(_update(), SIGNERS_BITMAP | 0x100) != base, "signersBitmap");
    }
}
