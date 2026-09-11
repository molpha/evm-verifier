// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.31;

import {Ownable} from "solady/auth/Ownable.sol";
import {SSTORE2} from "solady/utils/SSTORE2.sol";
import {LibBit} from "solady/utils/LibBit.sol";

import {LibSecp256k1} from "./libs/LibSecp256k1.sol";
import {LibSchnorr} from "./libs/LibSchnorr.sol";
import {IVerifier} from "./interfaces/IVerifier.sol";
import {PubkeyBlobLib} from "./libs/PubkeyBlobLib.sol";
import {VerifyCodes} from "./libs/VerifyCodes.sol";
import {VerifierLib} from "./libs/VerifierLib.sol";
import {KeysCommitmentLib} from "./libs/KeysCommitmentLib.sol";

/// @title Verifier
/// @notice Registry for managing nodes and verifying Schnorr signatures
/// @dev Uses SSTORE2 for efficient storage of node public keys, supports up to 256 nodes.
///      Every mutation publishes a new registry version; historical versions stay verifiable
///      until their successor's activation plus `PREVIOUS_GRACE`. See `docs/registry-v2.md`.
contract Verifier is IVerifier, Ownable {
    using LibSchnorr for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.Point;
    using VerifierLib for IVerifier.AttestationPayload;
    using VerifierLib for uint256;
    using PubkeyBlobLib for bytes;
    using LibBit for uint256;

    uint256 private constant MAX_NODES = 256;
    uint8 private constant NEVER = 0;
    uint8 private constant ACTIVE = 1;
    uint8 private constant RETIRED = 2;
    uint8 private constant OP_ADD = 1;
    uint8 private constant OP_REMOVE = 2;
    uint8 private constant OP_BUFFER = 3;

    /// @dev Seconds a retired version stays acceptable after its successor activates.
    uint256 private constant PREVIOUS_GRACE = 60;

    bytes32 private constant POP_DOMAIN = keccak256("MOLPHA_VERIFIER_V1");
    bytes32 private constant TRANSITION_DOMAIN = keccak256("MOLPHA_REGISTRY_TRANSITION_V1");
    bytes32 private constant GENESIS_ROOT = keccak256("MOLPHA_REGISTRY_GENESIS_V1");

    /// @dev Packed per-version state; see `VerifierLib` for the bit layout.
    ///      A zero entry means the version does not exist, since the key-blob pointer is never zero.
    mapping(uint256 version => uint256 entry) private registryEntries;
    mapping(uint256 version => bytes32 root) private registryRoots;
    mapping(address node => uint8 status) public nodeStatus;

    uint256 private registryVersionCount;

    constructor(address initialProtocolAdmin, uint256 initialRedundancyBuffer) {
        if (initialProtocolAdmin == address(0)) revert ZeroAdmin();
        if (initialRedundancyBuffer > MAX_NODES) {
            revert RedundancyBufferExceedsMax();
        }

        _initializeOwner(initialProtocolAdmin);

        LibSecp256k1.Point[] memory empty = new LibSecp256k1.Point[](0);
        address genesisPointer = SSTORE2.write(abi.encode(empty));
        // Genesis: activatesAt = 0.
        registryEntries[0] = VerifierLib.packEntry(genesisPointer, 0, initialRedundancyBuffer, 0, true);
        registryRoots[0] = GENESIS_ROOT;
    }

    // -------------------------------------------------------------------------
    // Verification
    // -------------------------------------------------------------------------

    /// @inheritdoc IVerifier
    function verify(Attestation calldata attestation, uint64 maxAge) external view returns (bool success, uint8 code) {
        // Both members are static structs, so these are compile-time calldata offsets, not copies.
        AttestationPayload calldata dataUpdate = attestation.payload;
        SchnorrSignature calldata schnorrData = attestation.signature;

        // Ordered cheapest-first: calldata-only checks, then hashing, then storage.
        if (dataUpdate.signaturesRequired == 0) return (false, VerifyCodes.R_MALFORMED);
        if (schnorrData.signersBitmap == 0) return (false, VerifyCodes.R_MALFORMED);
        if (schnorrData.signature == 0) return (false, VerifyCodes.R_MALFORMED);
        if (uint256(schnorrData.signature) >= LibSecp256k1.Q()) return (false, VerifyCodes.R_MALFORMED);
        if (schnorrData.commitment == address(0)) return (false, VerifyCodes.R_MALFORMED);
        if (schnorrData.signersBitmap.popCount() < dataUpdate.signaturesRequired) {
            return (false, VerifyCodes.R_MALFORMED);
        }

        // Freshness is defined against wall-clock time, so `block.timestamp` is the intended
        // reference; the caller opts in by passing a non-zero `maxAge` and chooses a window
        // wide enough to absorb the few seconds a proposer could shift it.
        // forge-lint: disable-start(block-timestamp)
        if (maxAge != 0) {
            uint256 ts = dataUpdate.canonicalTimestamp;
            if (ts > block.timestamp) return (false, VerifyCodes.R_MALFORMED);
            unchecked {
                if (block.timestamp - ts > maxAge) return (false, VerifyCodes.R_STALE);
            }
        }
        // forge-lint: disable-end(block-timestamp)

        uint256 entry = registryEntries[dataUpdate.registryVersion];
        if (entry == 0) return (false, VerifyCodes.R_BAD_REGISTRY_VERSION);

        if (dataUpdate.canonicalTimestamp < entry.activatesAt()) {
            return (false, VerifyCodes.R_NOT_YET_ACTIVE);
        }

        if (!entry.isLatest()) {
            uint256 successor = registryEntries[dataUpdate.registryVersion + 1];
            if (successor != 0 && dataUpdate.canonicalTimestamp > successor.activatesAt() + PREVIOUS_GRACE) {
                return (false, VerifyCodes.R_VERSION_EXPIRED);
            }
        }

        return _verifySignature(dataUpdate, schnorrData, entry);
    }

    // -------------------------------------------------------------------------
    // Registry administration
    // -------------------------------------------------------------------------

    /// @inheritdoc IVerifier
    function addNode(bytes memory compressedPubKey, SchnorrProof calldata pop) external onlyOwner {
        LibSecp256k1.Point memory pubkey = LibSecp256k1.decompress(compressedPubKey);
        if (pubkey.isZeroPoint()) revert InvalidPublicKey();

        address node = pubkey.toAddress();
        if (node == address(0)) revert ZeroAddress();
        if (nodeStatus[node] != NEVER) revert NodeNotEligible();

        uint256 registryVersion = registryVersionCount;
        uint256 entry = registryEntries[registryVersion];
        uint256 nodeCount = entry.nodeCount();
        if (nodeCount >= MAX_NODES) revert MaxNodesReached();

        _verifyPop(pubkey, compressedPubKey, pop);

        bytes memory keysBlob = SSTORE2.read(entry.pointerOf());
        keysBlob.addPubkey(pubkey);
        address newPointer = SSTORE2.write(keysBlob);

        _publishRegistryTransition(registryVersion, newPointer, nodeCount + 1, entry.buffer(), keysBlob, OP_ADD);

        nodeStatus[node] = ACTIVE;

        emit LogNodeAdded(node, nodeCount, newPointer);
    }

    /// @inheritdoc IVerifier
    function removeNode(address node, uint256 index) external override onlyOwner {
        _removeNodeAt(node, index);
    }

    /// @inheritdoc IVerifier
    function setRedundancyBuffer(uint256 newRedundancyBuffer) external override onlyOwner {
        if (newRedundancyBuffer > MAX_NODES) {
            revert RedundancyBufferExceedsMax();
        }

        uint256 registryVersion = registryVersionCount;
        uint256 entry = registryEntries[registryVersion];
        address pointer = entry.pointerOf();

        // The buffer feeds signer selection, so it is versioned state rather than a mutable
        // knob: the key blob carries forward untouched (registry-v2 §5.4).
        _publishRegistryTransition(
            registryVersion, pointer, entry.nodeCount(), newRedundancyBuffer, SSTORE2.read(pointer), OP_BUFFER
        );

        emit LogRedundancyBufferUpdated(newRedundancyBuffer);
    }

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

    /// @inheritdoc IVerifier
    function redundancyBuffer() external view returns (uint256) {
        return registryEntries[registryVersionCount].buffer();
    }

    /// @inheritdoc IVerifier
    function getRegistryVersion() external view returns (uint256) {
        return registryVersionCount;
    }

    /// @inheritdoc IVerifier
    function getRegistryPointer() external view returns (address) {
        return registryEntries[registryVersionCount].pointerOf();
    }

    /// @inheritdoc IVerifier
    function getRegistryPointer(uint256 registryVersion) external view returns (address registryPointer) {
        registryPointer = _existingEntry(registryVersion).pointerOf();
    }

    /// @inheritdoc IVerifier
    function getTotalNodes() external view override returns (uint256 totalSigners) {
        totalSigners = registryEntries[registryVersionCount].nodeCount();
    }

    /// @inheritdoc IVerifier
    function getRegistryRoot() external view returns (bytes32 root) {
        root = registryRoots[registryVersionCount];
    }

    /// @inheritdoc IVerifier
    function getRegistryRoot(uint256 registryVersion) external view returns (bytes32 root) {
        if (registryEntries[registryVersion] == 0) revert InvalidRegistryVersion();
        root = registryRoots[registryVersion];
    }

    /// @inheritdoc IVerifier
    function activatesAt(uint256 registryVersion) external view returns (uint256 ts) {
        ts = _existingEntry(registryVersion).activatesAt();
    }

    /// @inheritdoc IVerifier
    function retiredAt(uint256 registryVersion) external view returns (uint256 ts) {
        // Versions are dense, so a stored successor implies `registryVersion` itself exists;
        // an unknown or still-current version has none and reverts here.
        ts = _existingEntry(registryVersion + 1).activatesAt();
    }

    /// @inheritdoc IVerifier
    function isLatestVersion(uint256 registryVersion) external view returns (bool latest) {
        latest = _existingEntry(registryVersion).isLatest();
    }

    /// @inheritdoc IVerifier
    function isNode(address node) external view returns (bool) {
        return nodeStatus[node] == ACTIVE;
    }

    // -------------------------------------------------------------------------
    // Internals
    // -------------------------------------------------------------------------

    /// @dev Loads a registry entry, reverting when the version was never published.
    function _existingEntry(uint256 version) private view returns (uint256 entry) {
        entry = registryEntries[version];
        if (entry == 0) revert InvalidRegistryVersion();
    }

    /// @dev Swap-and-pop removal of blob index `index` from the current version.
    /// @return newVersion The version published by the removal.
    function _removeNodeAt(address node, uint256 index) private returns (uint256 newVersion) {
        uint256 registryVersion = registryVersionCount;
        uint256 entry = registryEntries[registryVersion];
        uint256 nodeCount = entry.nodeCount();
        if (nodeStatus[node] != ACTIVE) revert NodeNotEligible();
        if (nodeCount == 0 || index >= nodeCount) revert IndexWitnessMismatch();

        bytes memory keysBlob = SSTORE2.read(entry.pointerOf());
        if (node != keysBlob.getNode(index).toAddress()) revert IndexWitnessMismatch();

        // Index of the entry that gets swapped into the hole, and the post-removal count.
        uint256 last;
        unchecked {
            last = nodeCount - 1; // `nodeCount != 0` was just checked
        }

        nodeStatus[node] = RETIRED;

        keysBlob.removePubkey(index);
        address newPointer = SSTORE2.write(keysBlob);

        newVersion = _publishRegistryTransition(registryVersion, newPointer, last, entry.buffer(), keysBlob, OP_REMOVE);

        emit LogNodeRemoved(node, index, newPointer);
    }

    /// @dev Common transition tail (registry-v2 §5.1): stamps activation, commits the key set,
    ///      chains the root, and advances the version. Every mutation ends here.
    /// @param previousVersion Version being superseded.
    function _publishRegistryTransition(
        uint256 previousVersion,
        address newPointer,
        uint256 nodeCount,
        uint256 buffer,
        bytes memory keysBlob,
        uint8 op
    ) private returns (uint256 newVersion) {
        unchecked {
            newVersion = previousVersion + 1;
            uint256 activatesAtTs = block.timestamp;

            bytes32 commitment = KeysCommitmentLib.commitment(keysBlob);

            // Widths are fixed by the cross-chain preimage spec (registry-v2 §4); every value is
            // bounded well below its type (counts ≤ MAX_NODES, timestamp < 2^40 until year ~36800).
            // forge-lint: disable-start(unsafe-typecast)
            bytes32 newRoot = keccak256(
                abi.encodePacked(
                    TRANSITION_DOMAIN,
                    registryRoots[previousVersion],
                    uint32(newVersion),
                    commitment,
                    uint16(nodeCount),
                    uint16(buffer),
                    uint40(activatesAtTs)
                )
            );
            // forge-lint: disable-end(unsafe-typecast)

            registryRoots[newVersion] = newRoot;
            registryEntries[previousVersion] = registryEntries[previousVersion].withIsLatest(false);
            registryEntries[newVersion] = VerifierLib.packEntry(newPointer, nodeCount, buffer, activatesAtTs, true);
            registryVersionCount = newVersion;

            emit RegistryAdvanced(newVersion, newRoot, op);
        }
    }

    function _verifySignature(
        AttestationPayload calldata dataUpdate,
        SchnorrSignature calldata schnorrData,
        uint256 entry
    ) private view returns (bool success, uint8 code) {
        if (!dataUpdate.selectionOk(entry, schnorrData.signersBitmap)) {
            return (false, VerifyCodes.R_BAD_QUORUM);
        }

        // Aggregate over the full signersBitmap.
        LibSecp256k1.Point memory aggPubKey = entry.aggregatePubKey(schnorrData.signersBitmap);
        if (aggPubKey.isZeroPoint()) return (false, VerifyCodes.R_BAD_AGGREGATE);

        bytes32 message = dataUpdate.constructMessage(schnorrData.signersBitmap);
        if (!aggPubKey.verifySignatureTrusted(message, schnorrData.signature, schnorrData.commitment)) {
            return (false, VerifyCodes.R_BAD_SIGNATURE);
        }

        return (true, VerifyCodes.R_OK);
    }

    /// @dev Binds the proof to this deployment, so a PoP cannot be replayed onto another chain's verifier.
    function _verifyPop(LibSecp256k1.Point memory pubkey, bytes memory compressedPubKey, SchnorrProof calldata pop)
        private
        view
    {
        bytes32 digest = keccak256(abi.encodePacked(POP_DOMAIN, address(this), compressedPubKey));
        if (!pubkey.verifySignature(digest, pop.signature, pop.commitment)) revert InvalidPoP();
    }
}
