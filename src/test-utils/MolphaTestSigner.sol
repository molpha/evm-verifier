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
///      MolphaTestSigner signer = new MolphaTestSigner();
///      signer.registerNodes(8);
///      IVerifier.Attestation memory att =
///          signer.attest(SOURCE_ID, bytes32(uint256(1234)), 5, uint64(block.timestamp) * 1000);
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

    /// @dev Keys are derived from a running counter, so a node added after a removal never reuses
    ///      a removed node's key (the verifier would refuse it: a retired address stays retired).
    uint256 internal _nextKey = 1;

    constructor() {
        verifier = new Verifier(address(this));
    }

    /// @notice Register `count` deterministic nodes, each with a valid proof of possession.
    /// @dev Each takes the lowest free slot, as the verifier assigns it: a hole left by a removal,
    ///      else the slot after the last. Publishes one registry version per node.
    function registerNodes(uint256 count) external {
        for (uint256 i; i < count; ++i) {
            uint256 secret = MolphaSigLib.testSecret(_nextKey++);
            LibSecp256k1.Point memory pubkey = LibSecp256k1.mulAffine(LibSecp256k1.G(), secret);
            bytes memory compressed = LibSecp256k1.compress(pubkey);

            uint256 slot = _firstFreeSlot();
            if (slot == _pubkeys.length) {
                _secrets.push(secret);
                _pubkeys.push(pubkey);
            } else {
                _secrets[slot] = secret;
                _pubkeys[slot] = pubkey;
            }
            verifier.addNode(compressed, MolphaSigLib.proofOfPossession(address(verifier), compressed, secret));
        }
    }

    /// @notice Remove the node in `slot`, mirroring the registry locally: the slot becomes a hole,
    ///         no other node moves, and trailing holes are dropped.
    /// @dev The local key mirrors must track the on-chain blob or later attestations sign with the
    ///      wrong keys.
    function removeNode(uint256 slot) external {
        LibSecp256k1.Point memory removed = _pubkeys[slot];
        verifier.removeNode(removed.toAddress(), slot);

        delete _pubkeys[slot];
        delete _secrets[slot];
        while (_pubkeys.length != 0 && _pubkeys[_pubkeys.length - 1].x | _pubkeys[_pubkeys.length - 1].y == 0) {
            _pubkeys.pop();
            _secrets.pop();
        }
    }

    function _firstFreeSlot() internal view returns (uint256 slot) {
        for (; slot < _pubkeys.length; ++slot) {
            if (_pubkeys[slot].x | _pubkeys[slot].y == 0) break;
        }
    }

    /// @notice Key slots, holes included (the verifier's `getTotalNodes()`).
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
    function attest(bytes32 sourceId, bytes32 value, uint8 signaturesRequired, uint64 timestamp)
        external
        view
        returns (IVerifier.Attestation memory)
    {
        return attest(sourceId, value, signaturesRequired, signaturesRequired, timestamp);
    }

    /// @notice Kind B: sign `keccak256(encodedFields)`, leaving the consumer to carry the preimage.
    function attestFields(bytes32 sourceId, bytes memory encodedFields, uint8 signaturesRequired, uint64 timestamp)
        external
        view
        returns (IVerifier.Attestation memory)
    {
        return attest(sourceId, keccak256(encodedFields), signaturesRequired, signaturesRequired, timestamp);
    }

    /// @notice Sign with the lowest `signerCount` live nodes, which may exceed the threshold.
    function attest(bytes32 sourceId, bytes32 value, uint8 signaturesRequired, uint32 signerCount, uint64 timestamp)
        public
        view
        returns (IVerifier.Attestation memory)
    {
        IVerifier.AttestationPayload memory payload = IVerifier.AttestationPayload({
            value: value,
            sourceId: sourceId,
            registryVersion: uint32(verifier.getRegistryVersion()),
            signaturesRequired: uint8(signaturesRequired),
            timestamp: timestamp
        });
        return MolphaSigLib.buildAttestation(_secrets, _pubkeys, payload, signerCount);
    }
}
