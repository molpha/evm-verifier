// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";

import {IVerifier} from "../../src/interfaces/IVerifier.sol";
import {KeysCommitmentLib} from "../../src/libs/KeysCommitmentLib.sol";
import {NodeGroupBitmapLib} from "../../src/libs/NodeGroupBitmapLib.sol";
import {VerifierLib} from "../../src/libs/VerifierLib.sol";
import {Verifier} from "../../src/Verifier.sol";

/// @dev `constructMessage` and `getSelectionSeed` take calldata, so they need an external frame.
contract MessagePreimageHarness {
    function message(IVerifier.AttestationPayload calldata dataUpdate, uint256 signersBitmap)
        external
        pure
        returns (bytes32)
    {
        return VerifierLib.constructMessage(dataUpdate, signersBitmap);
    }

    function selectionSeed(IVerifier.AttestationPayload calldata dataUpdate) external pure returns (bytes32) {
        return VerifierLib.getSelectionSeed(dataUpdate);
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
    uint64 internal constant CANONICAL_TIMESTAMP = 1_699_965_440; // 0x65536a00

    bytes32 internal constant EXPECTED_MESSAGE = 0x7527b765799e48db80cefdd8c8cf76fd1e8feed2838eee5ba7ab862d920b5e61;
    bytes32 internal constant EXPECTED_SELECTION_SEED =
        0x24d3c035b75a33faa60438e66159dbb2011438056b4e86b892e6a89839b2a6fa;

    function _update() internal pure returns (IVerifier.AttestationPayload memory) {
        return IVerifier.AttestationPayload({
            sourceId: SOURCE_ID,
            registryVersion: REGISTRY_VERSION,
            signaturesRequired: SIGNATURES_REQUIRED,
            value: VALUE,
            canonicalTimestamp: CANONICAL_TIMESTAMP
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
            keccak256("MOLPHA_SELECTION_V1"),
            0x1def8159cbcfcdfd728d4197519a57c06e243f0d9468b4c1e5c4a233fc5653c3,
            "selection seed prefix"
        );
        assertEq(
            NodeGroupBitmapLib.SELECTION_DOMAIN,
            0x492848fe5e85d4ce2231d693a58f0820a4056e2822fe5dcad7c756afe044b70b,
            "selection derive domain"
        );
        assertEq(
            keccak256("MOLPHA_VERIFIER_V1"),
            0x789b999d1d38ea94308dd6904bfa70cf9ee14dd2b978fb6d2c894c9c84150a04,
            "proof-of-possession domain"
        );
        assertEq(
            keccak256("MOLPHA_REGISTRY_TRANSITION_V1"),
            0xdcdb8bfd549065dc5ed09759636ad21f9be4bb6f65c57dc668e2198c31f1636e,
            "registry transition domain"
        );
        assertEq(
            keccak256("MOLPHA_REGISTRY_GENESIS_V1"),
            0xc1d8611ff8d024c57f3f1797affc12d755596e27b3096334f6f8efb244b1afbf,
            "registry genesis root"
        );
    }

    function test_genesisRootIsTheDocumentedConstant() public {
        Verifier fresh = new Verifier(address(this), 2);
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
    ///      and `canonicalTimestamp` as 8, not as 32-byte words.
    function test_constructMessage_isSensitiveToFieldWidths() public view {
        bytes32 actual = harness.message(_update(), SIGNERS_BITMAP);

        bytes32 wordWidthVersion = keccak256(
            abi.encodePacked(
                keccak256("MOLPHA_MESSAGE_V1"),
                VALUE,
                SOURCE_ID,
                uint256(REGISTRY_VERSION),
                SIGNATURES_REQUIRED,
                CANONICAL_TIMESTAMP,
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
                CANONICAL_TIMESTAMP,
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
                uint256(CANONICAL_TIMESTAMP),
                SIGNERS_BITMAP
            )
        );
        assertTrue(actual != wordWidthTimestamp, "canonicalTimestamp must be encoded as uint64");
    }

    /// @dev Byte-for-byte fixture shared with `molpha-verifier/tests/fixtures/mod.rs` and the SDK.
    function test_constructMessage_matchesRustAndSdkSharedVector() public view {
        IVerifier.AttestationPayload memory payload = IVerifier.AttestationPayload({
            value: 0x12cd90a4cd4351a26f2bd02583d791ae1b1a3285853a3315e718db8d7b85a62d,
            sourceId: 0x41b87cd1b00231a5caebdfbc3e352d92bb0ec116335cc3544278a4bac95071a7,
            registryVersion: 12,
            signaturesRequired: 5,
            canonicalTimestamp: 1_705_257_421
        });
        assertEq(harness.message(payload, 0x0fa8), 0x52e92f58c9c128d2f7e0be6165c4d58f843c39e828c12fcad8cdc566152f2bb1);
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
        update.canonicalTimestamp = CANONICAL_TIMESTAMP + 1;
        assertTrue(harness.message(update, SIGNERS_BITMAP) != base, "canonicalTimestamp");

        assertTrue(harness.message(_update(), SIGNERS_BITMAP | 0x100) != base, "signersBitmap");
    }

    // ---------------------------------------------------------------------
    // Selection seed
    // ---------------------------------------------------------------------

    function test_getSelectionSeed_matchesTheSpecifiedDigest() public view {
        assertEq(harness.selectionSeed(_update()), EXPECTED_SELECTION_SEED);
    }

    /// @dev The seed deliberately covers only `(sourceId, registryVersion, canonicalTimestamp)`.
    ///      Signers derive the group before they know the coalition, so pulling `signersBitmap` or
    ///      `value` into the seed would make the selection unresolvable off chain.
    function test_getSelectionSeed_dependsOnRoundIdentityOnly() public view {
        bytes32 base = harness.selectionSeed(_update());

        IVerifier.AttestationPayload memory update = _update();
        update.signaturesRequired = SIGNATURES_REQUIRED + 1;
        assertEq(harness.selectionSeed(update), base, "signaturesRequired is outside the seed");

        update = _update();
        update.value = bytes32(uint256(0xfeed));
        assertEq(harness.selectionSeed(update), base, "value is outside the seed");

        update = _update();
        update.sourceId = bytes32(uint256(2));
        assertTrue(harness.selectionSeed(update) != base, "sourceId");

        update = _update();
        update.registryVersion = REGISTRY_VERSION + 1;
        assertTrue(harness.selectionSeed(update) != base, "registryVersion");

        update = _update();
        update.canonicalTimestamp = CANONICAL_TIMESTAMP + 1;
        assertTrue(harness.selectionSeed(update) != base, "canonicalTimestamp");
    }

    /// @dev The two preimages share their leading fields, so distinct domain prefixes are the only
    ///      thing keeping a selection seed from being reinterpreted as a signed message.
    function test_messageAndSelectionSeedAreDomainSeparated() public view {
        assertTrue(harness.message(_update(), SIGNERS_BITMAP) != harness.selectionSeed(_update()));
    }
}
