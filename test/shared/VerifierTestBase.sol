// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";

import {Verifier} from "../../src/Verifier.sol";
import {IVerifier} from "../../src/interfaces/IVerifier.sol";
import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";
import {NodeGroupBitmapLib} from "../../src/libs/NodeGroupBitmapLib.sol";
import {LibSchnorrTestSign} from "../libs/LibSchnorrTestSign.sol";

abstract contract VerifierTestBase is Test {
    using LibSecp256k1 for LibSecp256k1.Point;

    bytes32 internal constant POP_DOMAIN = keccak256("MOLPHA_VALIDATOR_V1");
    bytes32 internal constant MESSAGE_PREFIX = keccak256("MOLPHA_MESSAGE_V1");
    bytes32 internal constant SELECTION_SEED_PREFIX = keccak256("MOLPHA_SELECTION_V1");

    Verifier internal verifier;
    uint256[] internal secrets;
    LibSecp256k1.Point[] internal pubkeys;

    function setUp() public virtual {
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

    function _selectionSeed(IVerifier.DataUpdate memory update) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(SELECTION_SEED_PREFIX, update.feedId, update.registryVersion, update.canonicalTimestamp)
        );
    }

    function _message(IVerifier.DataUpdate memory update, uint256 signersBitmap) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                MESSAGE_PREFIX,
                update.feedId,
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
        for (uint256 position; position < registeredNodes && found < count; ++position) {
            if (bitmap & (uint256(1) << position) != 0) {
                indices[found++] = position + 1;
            }
        }
        require(found == count, "insufficient selected signers");
    }

    function _sumPubkeys(uint256[] memory indices) internal view returns (LibSecp256k1.Point memory aggregate) {
        require(indices.length != 0, "empty signer set");
        aggregate = pubkeys[indices[0] - 1];
        for (uint256 i = 1; i < indices.length; ++i) {
            LibSecp256k1.Point memory next = pubkeys[indices[i] - 1];
            (uint256 x, uint256 y, uint256 z) =
                LibSecp256k1.addAffinePointToXYZ(aggregate.x, aggregate.y, 1, next.x, next.y);
            aggregate = LibSecp256k1.toAffineModexpXYZ(x, y, z);
        }
    }

    function _sumSecrets(uint256[] memory indices) internal view returns (uint256 aggregateSecret) {
        for (uint256 i; i < indices.length; ++i) {
            aggregateSecret = addmod(aggregateSecret, secrets[indices[i] - 1], LibSecp256k1.Q());
        }
    }

    function _buildVerifyCall(
        Verifier target,
        uint256 signaturesRequired,
        uint256 signerCount,
        bytes32 feedId,
        bytes32 value,
        uint64 canonicalTimestamp
    ) internal view returns (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) {
        update = IVerifier.DataUpdate({
            feedId: feedId,
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
            signersBitmap |= uint256(1) << (indices[i] - 1);
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
        bytes32 feedId,
        bytes32 value,
        uint64 canonicalTimestamp
    ) internal view returns (IVerifier.DataUpdate memory update, IVerifier.SchnorrSignature memory schnorr) {
        return _buildVerifyCall(target, signaturesRequired, signaturesRequired, feedId, value, canonicalTimestamp);
    }
}
