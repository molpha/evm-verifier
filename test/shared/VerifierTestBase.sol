// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";
import {SSTORE2} from "solady/utils/SSTORE2.sol";

import {Verifier} from "../../src/Verifier.sol";
import {PubkeyBlobLib} from "../../src/libs/PubkeyBlobLib.sol";
import {IVerifier} from "../../src/interfaces/IVerifier.sol";
import {VerifyCodes} from "../../src/libs/VerifyCodes.sol";
import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";
import {NodeGroupBitmapLib} from "../../src/libs/NodeGroupBitmapLib.sol";
import {KeysCommitmentLib} from "../../src/libs/KeysCommitmentLib.sol";
import {LibSchnorrTestSign} from "../libs/LibSchnorrTestSign.sol";

abstract contract VerifierTestBase is Test {
    using LibSecp256k1 for LibSecp256k1.Point;
    using PubkeyBlobLib for bytes;

    error EmptySignerSet();
    error InsufficientSelectedSigners();

    bytes32 internal constant POP_DOMAIN = keccak256("MOLPHA_VERIFIER_V1");
    bytes32 internal constant MESSAGE_PREFIX = keccak256("MOLPHA_MESSAGE_V1");
    bytes32 internal constant SELECTION_SEED_PREFIX = keccak256("MOLPHA_SELECTION_V1");
    bytes32 internal constant TRANSITION_DOMAIN = keccak256("MOLPHA_REGISTRY_TRANSITION_V1");
    bytes32 internal constant GENESIS_ROOT = keccak256("MOLPHA_REGISTRY_GENESIS_V1");
    uint8 internal constant NEVER = 0;
    uint8 internal constant ACTIVE = 1;
    uint8 internal constant RETIRED = 2;
    uint8 internal constant COMPROMISED = 3;
    uint256 internal constant SKIP_CURRENT_INDEX = type(uint256).max;

    /// @dev Matches Foundry warps used across unit tests so `activatesAt` and signed
    ///      `canonicalTimestamp` values share a coherent window.
    uint256 internal constant BASE_TIME = 1_700_000_000;
    uint256 internal constant PREVIOUS_GRACE = 60;

    Verifier internal verifier;
    uint256[] internal secrets;
    LibSecp256k1.Point[] internal pubkeys;

    function setUp() public virtual {
        vm.warp(BASE_TIME);
        verifier = new Verifier(address(this), 2);
    }

    function _secret(uint256 slot) internal pure returns (uint256) {
        return (uint256(keccak256(abi.encodePacked("MOLPHA_VERIFIER_TEST_KEY", slot))) % (LibSecp256k1.Q() - 1)) + 1;
    }

    function _proofOfPossession(address verifierAddress, bytes memory compressedPubkey, uint256 secret)
        internal
        view
        returns (IVerifier.SchnorrProof memory proof)
    {
        bytes32 digest = keccak256(abi.encodePacked(POP_DOMAIN, verifierAddress, compressedPubkey));
        LibSecp256k1.Point memory pubkey = LibSecp256k1.decompress(compressedPubkey);
        (bytes32 signature, address commitment) = LibSchnorrTestSign.sign(pubkey, secret, digest, 0);
        proof = IVerifier.SchnorrProof({signature: signature, commitment: commitment});
    }

    function _appendNode(Verifier target, uint256 slot) internal returns (address node) {
        uint256 secret = _secret(slot);
        LibSecp256k1.Point memory pubkey = LibSecp256k1.mulAffine(LibSecp256k1.G(), secret);
        bytes memory compressedPubkey = LibSecp256k1.compress(pubkey);

        secrets.push(secret);
        pubkeys.push(pubkey);
        target.addNode(compressedPubkey, _proofOfPossession(address(target), compressedPubkey, secret));
        node = pubkey.toAddress();
    }

    function _addNodes(Verifier target, uint256 count) internal {
        delete secrets;
        delete pubkeys;
        for (uint256 i; i < count; ++i) {
            _appendNode(target, i + 1);
        }
    }

    function _removeNode(Verifier target, uint256 index) internal {
        bytes memory blob = SSTORE2.read(target.getRegistryPointer());
        address node = blob.getNode(index).toAddress();
        target.removeNode(node, index);
    }

    /// @dev `_removeNode` plus the same swap-and-pop applied to the local `secrets`/`pubkeys`
    ///      mirrors. `_buildVerifyCall` addresses keys by live blob index, so a test that signs
    ///      after a removal must keep the mirrors aligned or it will sign with the wrong keys.
    function _removeNodeMirrored(Verifier target, uint256 index) internal {
        _removeNode(target, index);

        uint256 last = pubkeys.length - 1;
        if (index != last) {
            pubkeys[index] = pubkeys[last];
            secrets[index] = secrets[last];
        }
        pubkeys.pop();
        secrets.pop();
    }

    function _selectionSeed(IVerifier.DataUpdate memory update) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(SELECTION_SEED_PREFIX, update.sourceId, update.registryVersion, update.canonicalTimestamp)
        );
    }

    function _message(IVerifier.DataUpdate memory update, uint256 signersBitmap) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                MESSAGE_PREFIX,
                update.sourceId,
                update.registryVersion,
                update.signaturesRequired,
                signersBitmap,
                update.value,
                update.canonicalTimestamp
            )
        );
    }

    function _pickSignerIndices(uint256 bitmap, uint256 registeredNodes, uint256 count)
        internal
        pure
        returns (uint256[] memory indices)
    {
        indices = new uint256[](count);
        uint256 found;
        for (uint256 position; position < registeredNodes; ++position) {
            if (bitmap & (uint256(1) << position) == 0) continue;
            indices[found] = position;
            unchecked {
                ++found;
            }
            if (found == count) return indices;
        }
        revert InsufficientSelectedSigners();
    }

    function _sumPubkeys(uint256[] memory indices) internal view returns (LibSecp256k1.Point memory aggregate) {
        if (indices.length == 0) revert EmptySignerSet();
        aggregate = pubkeys[indices[0]];
        for (uint256 i = 1; i < indices.length; ++i) {
            LibSecp256k1.Point memory next = pubkeys[indices[i]];
            (uint256 x, uint256 y, uint256 z) =
                LibSecp256k1.addAffinePointToXYZ(aggregate.x, aggregate.y, 1, next.x, next.y);
            aggregate = LibSecp256k1.toAffineModexpXYZ(x, y, z);
        }
    }

    function _sumSecrets(uint256[] memory indices) internal view returns (uint256 aggregateSecret) {
        for (uint256 i; i < indices.length; ++i) {
            aggregateSecret = addmod(aggregateSecret, secrets[indices[i]], LibSecp256k1.Q());
        }
    }

    function _buildVerifyCall(
        Verifier target,
        uint256 signaturesRequired,
        uint256 signerCount,
        bytes32 sourceId,
        bytes32 value,
        uint64 canonicalTimestamp
    ) internal view returns (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) {
        update = IVerifier.DataUpdate({
            sourceId: sourceId,
            registryVersion: uint32(target.getRegistryVersion()),
            signaturesRequired: uint32(signaturesRequired),
            value: value,
            canonicalTimestamp: canonicalTimestamp
        });

        uint256 registeredNodes = target.getTotalNodes();
        uint256 groupSize = signaturesRequired + target.redundancyBuffer();
        if (groupSize > registeredNodes) groupSize = registeredNodes;

        uint256 selectionBitmap = NodeGroupBitmapLib.derive(_selectionSeed(update), registeredNodes, groupSize);
        uint256[] memory indices = _pickSignerIndices(selectionBitmap, registeredNodes, signerCount);

        uint256 signersBitmap;
        for (uint256 i; i < indices.length; ++i) {
            signersBitmap |= uint256(1) << indices[i];
        }

        LibSecp256k1.Point memory aggregatePubkey = _sumPubkeys(indices);
        (bytes32 signature, address commitment) =
            LibSchnorrTestSign.sign(aggregatePubkey, _sumSecrets(indices), _message(update, signersBitmap), 0);
        schnorr =
            IVerifier.SchnorrSignature({signature: signature, commitment: commitment, signersBitmap: signersBitmap});
    }

    function _buildVerifyCall(
        Verifier target,
        uint256 signaturesRequired,
        bytes32 sourceId,
        bytes32 value,
        uint64 canonicalTimestamp
    ) internal view returns (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) {
        return _buildVerifyCall(target, signaturesRequired, signaturesRequired, sourceId, value, canonicalTimestamp);
    }

    function _buildVerifyCall(Verifier target, uint256 signaturesRequired, bytes32 sourceId, bytes32 value)
        internal
        view
        returns (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr)
    {
        return _buildVerifyCall(target, signaturesRequired, sourceId, value, uint64(block.timestamp));
    }

    function _verify(Verifier target, IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr)
        internal
        view
        returns (bool ok, uint8 code)
    {
        return target.verify(update, schnorr, 0);
    }

    function _verify(
        Verifier target,
        IVerifier.DataUpdate memory update,
        IVerifier.SchnorrSignature memory schnorr,
        uint256 maxAge
    ) internal view returns (bool ok, uint8 code) {
        return target.verify(update, schnorr, maxAge);
    }

    function _assertVerifyOk(
        Verifier target,
        IVerifier.DataUpdate memory update,
        IVerifier.SchnorrSignature memory schnorr
    ) internal view {
        (bool ok, uint8 code) = _verify(target, update, schnorr);
        assertTrue(ok);
        assertEq(code, VerifyCodes.R_OK);
    }

    function _assertVerifyOk(
        Verifier target,
        IVerifier.DataUpdate memory update,
        IVerifier.SchnorrSignature memory schnorr,
        uint256 maxAge
    ) internal view {
        (bool ok, uint8 code) = _verify(target, update, schnorr, maxAge);
        assertTrue(ok);
        assertEq(code, VerifyCodes.R_OK);
    }

    function _assertVerifyFails(
        Verifier target,
        IVerifier.DataUpdate memory update,
        IVerifier.SchnorrSignature memory schnorr
    ) internal view {
        (bool ok,) = _verify(target, update, schnorr);
        assertFalse(ok);
    }

    function _assertVerifyFails(
        Verifier target,
        IVerifier.DataUpdate memory update,
        IVerifier.SchnorrSignature memory schnorr,
        uint8 expectedCode
    ) internal view {
        (bool ok, uint8 code) = _verify(target, update, schnorr);
        assertFalse(ok);
        assertEq(code, expectedCode);
    }

    function _assertVerifyFails(
        Verifier target,
        IVerifier.DataUpdate memory update,
        IVerifier.SchnorrSignature memory schnorr,
        uint256 maxAge,
        uint8 expectedCode
    ) internal view {
        (bool ok, uint8 code) = _verify(target, update, schnorr, maxAge);
        assertFalse(ok);
        assertEq(code, expectedCode);
    }

    function _expectedRegistryRoot(
        bytes32 prevRoot,
        uint256 newVersion,
        bytes32 commitment,
        uint256 nodeCount,
        uint256 buffer,
        uint256 activatesAtTs
    ) internal pure returns (bytes32 root) {
        root = keccak256(
            abi.encodePacked(
                TRANSITION_DOMAIN,
                prevRoot,
                uint32(newVersion),
                commitment,
                uint16(nodeCount),
                uint16(buffer),
                uint40(activatesAtTs)
            )
        );
    }

    /// @dev Keys commitment for a registry version, derived from its immutable SSTORE2 blob.
    function _keysCommitmentAt(Verifier target) internal view returns (bytes32) {
        return KeysCommitmentLib.commitment(SSTORE2.read(target.getRegistryPointer()));
    }

    function _keysCommitmentAt(Verifier target, uint256 version) internal view returns (bytes32) {
        return KeysCommitmentLib.commitment(SSTORE2.read(target.getRegistryPointer(version)));
    }

    /// @dev Independent coordinate-hash of the given pubkeys in order (same as KeysCommitmentLib).
    function _keysCommitmentOf(LibSecp256k1.Point[] memory points) internal pure returns (bytes32) {
        if (points.length == 0) return KeysCommitmentLib.emptyCommitment();
        bytes memory coords = new bytes(points.length * 64);
        for (uint256 i; i < points.length; ++i) {
            bytes32 x = bytes32(points[i].x);
            bytes32 y = bytes32(points[i].y);
            assembly ("memory-safe") {
                let off := add(add(coords, 0x20), mul(i, 64))
                mstore(off, x)
                mstore(add(off, 0x20), y)
            }
        }
        return keccak256(coords);
    }

    /// @dev Map a 0-based blob index to the secret used when that node was appended.
    function _secretAtBlobIndex(uint256 blobIndex) internal view returns (uint256) {
        return secrets[blobIndex];
    }
}
