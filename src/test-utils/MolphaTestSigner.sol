// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.31;

import {IVerifier} from "../interfaces/IVerifier.sol";
import {LibSecp256k1} from "../libs/LibSecp256k1.sol";
import {Verifier} from "../Verifier.sol";
import {MolphaSigLib} from "./MolphaSigLib.sol";

/// @title MolphaTestSigner
/// @notice A local `Verifier` with real keys, for integration-testing a consumer against genuine
///         Schnorr signatures instead of a mock.
/// @dev Deploy it, register nodes, ask for an attestation:
///
///      ```solidity
///      MolphaTestSigner signer = new MolphaTestSigner(2);
///      signer.registerNodes(8);
///      IVerifier.Attestation memory att =
///          signer.attest(SOURCE_ID, bytes32(uint256(1234)), 5, uint64(block.timestamp));
///      ```
///
///      Uses no cheatcodes, so it works from any contract and needs no forge-std. It owns the
///      `Verifier` it deploys, which is what lets it register nodes without pranking. Test-only:
///      keys are deterministic and public. Pinned to `^0.8.31` because it deploys the real
///      `Verifier`; consumers on older compilers should use `MockVerifier`.
contract MolphaTestSigner {
    using LibSecp256k1 for LibSecp256k1.Point;

    /// @notice The local verifier. Pass `IVerifier(address(signer.verifier()))` to the consumer.
    Verifier public immutable verifier;

    uint256[] internal _secrets;
    LibSecp256k1.Point[] internal _pubkeys;

    constructor(uint256 redundancyBuffer) {
        verifier = new Verifier(address(this), redundancyBuffer);
    }

    /// @notice Register `count` deterministic nodes, each with a valid proof of possession.
    /// @dev Appends to any already registered. Publishes one registry version per node.
    function registerNodes(uint256 count) external {
        uint256 base = _pubkeys.length;
        for (uint256 i; i < count; ++i) {
            uint256 secret = MolphaSigLib.testSecret(base + i + 1);
            LibSecp256k1.Point memory pubkey = LibSecp256k1.mulAffine(LibSecp256k1.G(), secret);
            bytes memory compressed = LibSecp256k1.compress(pubkey);

            _secrets.push(secret);
            _pubkeys.push(pubkey);
            verifier.addNode(compressed, MolphaSigLib.proofOfPossession(address(verifier), compressed, secret));
        }
    }

    /// @notice Remove the node at `blobIndex`, mirroring the registry's swap-and-pop locally.
    /// @dev The local key mirrors must track the on-chain blob or later attestations sign with the
    ///      wrong keys.
    function removeNode(uint256 blobIndex) external {
        LibSecp256k1.Point memory removed = _pubkeys[blobIndex];
        verifier.removeNode(removed.toAddress(), blobIndex);

        uint256 last = _pubkeys.length - 1;
        if (blobIndex != last) {
            _pubkeys[blobIndex] = _pubkeys[last];
            _secrets[blobIndex] = _secrets[last];
        }
        _pubkeys.pop();
        _secrets.pop();
    }

    /// @notice Change the redundancy buffer, publishing a new registry version.
    function setRedundancyBuffer(uint256 newBuffer) external {
        verifier.setRedundancyBuffer(newBuffer);
    }

    function nodeCount() external view returns (uint256) {
        return _pubkeys.length;
    }

    function secretAt(uint256 blobIndex) external view returns (uint256) {
        return _secrets[blobIndex];
    }

    function pubkeyAt(uint256 blobIndex) external view returns (LibSecp256k1.Point memory) {
        return _pubkeys[blobIndex];
    }

    /// @notice Kind A: sign `value` as the result word itself.
    function attest(bytes32 sourceId, bytes32 value, uint8 signaturesRequired, uint64 canonicalTimestamp)
        external
        view
        returns (IVerifier.Attestation memory)
    {
        return attest(sourceId, value, signaturesRequired, signaturesRequired, canonicalTimestamp);
    }

    /// @notice Kind B: sign `keccak256(encodedFields)`, leaving the consumer to carry the preimage.
    function attestFields(
        bytes32 sourceId,
        bytes memory encodedFields,
        uint8 signaturesRequired,
        uint64 canonicalTimestamp
    ) external view returns (IVerifier.Attestation memory) {
        return attest(sourceId, keccak256(encodedFields), signaturesRequired, signaturesRequired, canonicalTimestamp);
    }

    /// @notice Sign with `signerCount` of the selected group, which may exceed the threshold.
    function attest(
        bytes32 sourceId,
        bytes32 value,
        uint8 signaturesRequired,
        uint32 signerCount,
        uint64 canonicalTimestamp
    ) public view returns (IVerifier.Attestation memory) {
        IVerifier.AttestationPayload memory payload = IVerifier.AttestationPayload({
            value: value,
            sourceId: sourceId,
            registryVersion: uint32(verifier.getRegistryVersion()),
            signaturesRequired: uint8(signaturesRequired),
            canonicalTimestamp: canonicalTimestamp
        });
        return MolphaSigLib.buildAttestation(_secrets, _pubkeys, payload, verifier.redundancyBuffer(), signerCount);
    }
}
