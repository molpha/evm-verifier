// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.31;

/// @title IVerifier
/// @notice Interface for the Verifier
interface IVerifier {
    /// @notice Generic Schnorr proof data used for PoP and aggregate verification inputs.
    /// @param signature Schnorr scalar `s`
    /// @param commitment Ethereum address of commitment point `R`
    struct SchnorrProof {
        bytes32 signature;
        address commitment;
    }

    /// @notice Schnorr signature data struct containing aggregated signature information
    /// @dev `signersBitmap` uses 0-based bit positions: bit (i-1) set iff 1-based signer index i signed.
    ///      At most 256 nodes; bits outside the active node count must be zero.
    /// @param signature The aggregated Schnorr signature
    /// @param commitment The commitment point used in the signature
    /// @param signersBitmap Bitmap of participating signer indices (1-based index i → bit i-1)
    struct SchnorrSignature {
        bytes32 signature;
        address commitment;
        uint256 signersBitmap;
    }

    struct DataUpdate {
        bytes32 jobId;
        uint32 registryVersion;
        uint32 signaturesRequired;
        bytes32 value;
        uint64 canonicalTimestamp;
    }

    /// @notice Emitted when a new node is added to the set
    /// @param node The address of the new node
    /// @param index The index assigned to the new node
    /// @param rawKeysPointer The storage pointer to the updated raw keys array
    event LogNodeAdded(address indexed node, uint256 index, address rawKeysPointer);

    /// @notice Emitted when a node is removed from the set
    /// @param node The address of the removed node
    /// @param oldIndex The previous index of the removed node
    /// @param rawKeysPointer The storage pointer to the updated raw keys array
    event LogNodeRemoved(address indexed node, uint256 oldIndex, address rawKeysPointer);

    /// @notice Emitted when the minimum signatures threshold is updated
    /// @param newThreshold The new minimum number of signatures required
    event LogThresholdUpdated(uint256 newThreshold);

    /// @notice Emitted when the protocol admin role is transferred
    /// @param previousAdmin The previous protocol admin
    /// @param newAdmin The new protocol admin
    event LogProtocolAdminTransferred(address indexed previousAdmin, address indexed newAdmin);

    /// @notice Emitted when the redundancy buffer is updated
    /// @param newRedundancyBuffer The new redundancy buffer value
    event LogRedundancyBufferUpdated(uint256 newRedundancyBuffer);

    /// @notice Emitted after a successful publish to a feed
    event LogAnswerPublished(
        address indexed feed,
        bytes value,
        uint64 timestamp,
        bytes32 signersBitmap,
        uint32 round,
        bytes32 seed
    );

    /// @notice Emitted when the global participation map hash is updated
    event LogParticipationUpdated(bytes32 newHash, uint32[] updatedMap);

    /// @notice Emitted when per-job oracle state is first initialized
    event LogJobInitialized(bytes32 indexed jobId, bytes32 initialSeed);

    /// @notice Add a new node in the aggregator group
    /// @param compressedPubKey Compressed public key of the node
    /// @param pop Schnorr proof-of-possession by the same key over the registration domain message
    function addNode(bytes memory compressedPubKey, SchnorrProof calldata pop) external;

    /// @notice Remove a node from the aggregator group
    /// @param node Address of the node to remove
    function removeNode(address node) external;

    /// @notice Transfer the protocol admin role to a new address
    /// @param newProtocolAdmin The address of the new protocol admin
    function transferProtocolAdmin(address newProtocolAdmin) external;

    /// @notice Set the redundancy buffer used when deriving the signer group size
    /// @param newRedundancyBuffer The new redundancy buffer (`groupSize = signaturesRequired + redundancyBuffer`)
    function setRedundancyBuffer(uint256 newRedundancyBuffer) external;

    /// @notice Verify a Schnorr signature
    /// @param dataUpdate The data update
    /// @param schnorrData The Schnorr signature data
    /// @notice Reverts if verification fails. Not `view`: publish path records participation in the same pass.
    function verify(
        DataUpdate calldata dataUpdate,
        SchnorrSignature calldata schnorrData
    ) external view returns (bool);

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

    /// @notice Check if a node is currently registered
    /// @param node Address of the node
    /// @return isActive Whether the node is active
    function isNode(address node) external view returns (bool isActive);

    /// @notice Get the total number of nodes in the aggregator group
    /// @return totalNodes The total number of nodes
    function getTotalNodes() external view returns (uint256 totalNodes);

    /// @notice Get the hash of the nodes set
    /// @return hash The hash of the nodes set
    function getNodesSetHash() external view returns (bytes32 hash);

    /// @notice Plain-sum aggregate pubkey over the full registered signer set (uncompressed x, y)
    function getAggregateKey() external view returns (uint256 x, uint256 y);

    /// @notice Get the index of a node (alternative name for compatibility)
    /// @param node Address of the node
    /// @return index The index of the node
    function getNodeIndex(address node) external view returns (uint256 index);
}
