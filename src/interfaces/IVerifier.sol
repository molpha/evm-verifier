// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.31;

/// @title IVerifier
/// @notice Interface for the Verifier
interface IVerifier {
    error InvalidPoP();
    error InvalidPublicKey();
    error InvalidRegistryVersion();
    error MaxNodesReached();
    error NodeNotEligible();
    error IndexWitnessMismatch();
    error RedundancyBufferExceedsMax();
    error ZeroAddress();
    error ZeroAdmin();
    error KeyAlreadyCompromised();
    error KeyNotCompromised();
    error InvalidPrivateKeyScalar();
    error WitnessMismatch();
    error MissingCurrentIndex();
    error AlreadyCounted();

    /// @notice Generic Schnorr proof data used for PoP and aggregate verification inputs.
    /// @param signature Schnorr scalar `s`
    /// @param commitment Ethereum address of commitment point `R`
    struct SchnorrProof {
        bytes32 signature;
        address commitment;
    }

    /// @notice Schnorr signature data struct containing aggregated signature information
    /// @dev `signersBitmap` uses 0-based bit positions: bit i set iff blob index i signed.
    ///      At most 256 nodes; bits outside the active node count must be zero.
    /// @param signature The aggregated Schnorr signature
    /// @param commitment The commitment point used in the signature
    /// @param signersBitmap Bitmap of participating signer indices (bit i ↔ 0-based blob index i)
    struct SchnorrSignature {
        bytes32 signature;
        address commitment;
        uint256 signersBitmap;
    }

    /// @notice Data update struct containing the data update information
    /// @param value The value of the data update
    /// @param sourceId Canonical data source identifier
    /// @param registryVersion The registry version
    /// @param signaturesRequired The number of signatures required
    /// @param canonicalTimestamp The canonical timestamp of the data update
    struct DataUpdate {
        bytes32 value;
        bytes32 sourceId;
        uint32 registryVersion;
        uint32 signaturesRequired;
        uint64 canonicalTimestamp;
    }

    /// @notice Emitted when a new node is added to the set
    /// @param node The address of the new node
    /// @param index The 0-based blob index assigned to the new node
    /// @param rawKeysPointer The storage pointer to the updated raw keys array
    event LogNodeAdded(address indexed node, uint256 index, address rawKeysPointer);

    /// @notice Emitted when a node is removed from the set
    /// @param node The address of the removed node
    /// @param oldIndex The previous 0-based blob index of the removed node
    /// @param rawKeysPointer The storage pointer to the updated raw keys array
    event LogNodeRemoved(address indexed node, uint256 oldIndex, address rawKeysPointer);

    /// @notice Emitted when the redundancy buffer is updated
    /// @param newRedundancyBuffer The new redundancy buffer value
    event LogRedundancyBufferUpdated(uint256 newRedundancyBuffer);

    /// @notice Emitted after every registry mutation from the common transition tail
    event RegistryAdvanced(uint256 indexed newVersion, bytes32 newRoot, uint8 op);

    /// @notice Emitted when a private key is proven compromised
    event KeyCompromised(address indexed node, uint256 witnessVersion, uint256 witnessIndex);

    /// @notice Emitted when a compromised key is seeded into a historical version bitmap
    event CompromiseBackfilled(address indexed node, uint256 version, uint256 index);

    /// @notice Emitted when a flagged node is permissionlessly removed
    event FlaggedNodeRemoved(uint256 indexed newVersion, address indexed node);

    /// @notice Add a new node to the verifier
    /// @param compressedPubKey Compressed public key of the node
    /// @param pop Schnorr proof-of-possession by the same key over the registration domain message
    function addNode(bytes memory compressedPubKey, SchnorrProof calldata pop) external;

    /// @notice Remove a node from the verifier
    /// @param node The address of the node to remove
    /// @param index 0-based blob index of the node to remove
    function removeNode(address node, uint256 index) external;

    /// @notice Set the redundancy buffer used when deriving the signer group size
    /// @dev Publishes a new registry version rather than editing the current one, so a signature
    ///      that verified under the old buffer keeps verifying against its own version.
    /// @param newRedundancyBuffer The new redundancy buffer (`groupSize = signaturesRequired + redundancyBuffer`)
    function setRedundancyBuffer(uint256 newRedundancyBuffer) external;

    /// @notice The redundancy buffer in force for the current registry version
    function redundancyBuffer() external view returns (uint256);

    /// @notice Prove a node private key is public and seed compromised bitmaps
    /// @param privKey Leaked secp256k1 scalar
    /// @param witnessVersion Registry version containing the key
    /// @param witnessIndex 0-based blob index within that version
    /// @param currentIndex 0-based blob index in the live version; required when the node is
    ///        `ACTIVE`, or `type(uint256).max` when the node is `RETIRED` and absent from the live blob
    function flagCompromisedKey(uint256 privKey, uint256 witnessVersion, uint256 witnessIndex, uint256 currentIndex)
        external;

    /// @notice Seed a compromised key into a version the flag did not reach
    /// @param node Compromised node address
    /// @param version Registry version to seed
    /// @param index 0-based blob index within that version
    function backfillCompromised(address node, uint256 version, uint256 index) external;

    /// @notice Permissionlessly remove a currently-registered compromised node
    /// @param index 0-based blob index of the node to remove
    /// @param node The address of the node to remove
    function removeFlagged(uint256 index, address node) external;

    /// @notice Verify a Schnorr signature
    /// @param dataUpdate The data update
    /// @param schnorrData The Schnorr signature data
    /// @param maxAge Maximum age in seconds for `dataUpdate.canonicalTimestamp` relative to
    ///        `block.timestamp`. Pass `0` to skip the freshness check.
    /// @return success True when the signature is valid
    /// @return code Result code; see `VerifyCodes`
    function verify(DataUpdate calldata dataUpdate, SchnorrSignature calldata schnorrData, uint256 maxAge)
        external
        view
        returns (bool success, uint8 code);

    /// @notice Get the current registry version
    /// @return registryVersion The current registry version
    function getRegistryVersion() external view returns (uint256 registryVersion);

    /// @notice Get the current registry pointer
    /// @return registryPointer The current registry pointer
    function getRegistryPointer() external view returns (address registryPointer);

    /// @notice Get the registry pointer for a specific registry version
    /// @param registryVersion The registry version
    /// @return registryPointer The registry pointer for the specific registry version
    function getRegistryPointer(uint256 registryVersion) external view returns (address registryPointer);

    /// @notice Get the total number of nodes in the verifier
    /// @return totalNodes The total number of nodes
    function getTotalNodes() external view returns (uint256 totalNodes);

    /// @notice Membership status of `node`: `0` never, `1` active, `2` retired, `3` compromised
    function nodeStatus(address node) external view returns (uint8);

    /// @notice Whether `node` is currently registered in the live registry version
    function isNode(address node) external view returns (bool);

    /// @notice Get the chained registry root for the current version
    /// @return root The registry root
    function getRegistryRoot() external view returns (bytes32 root);

    /// @notice Get the chained registry root for a specific registry version
    /// @param registryVersion The registry version
    /// @return root The registry root
    function getRegistryRoot(uint256 registryVersion) external view returns (bytes32 root);

    /// @notice Activation timestamp for a registry version (`block.timestamp` at publish)
    /// @param registryVersion The registry version
    /// @return ts Unix seconds when the version became live
    function activatesAt(uint256 registryVersion) external view returns (uint256 ts);

    /// @notice Retirement timestamp for a registry version (`activatesAt` of the successor)
    /// @param registryVersion The registry version
    /// @return ts Unix seconds when the version was superseded
    function retiredAt(uint256 registryVersion) external view returns (uint256 ts);

    /// @notice Whether `registryVersion` is the current head of the version chain
    /// @param registryVersion The registry version
    /// @return latest True when this version is the live registry head
    function isLatestVersion(uint256 registryVersion) external view returns (bool latest);
}
