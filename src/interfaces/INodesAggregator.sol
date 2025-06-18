// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {LibSecp256k1} from "../libs/LibSecp256k1.sol";
import {ICommonErrors} from "./ICommonErrors.sol";

/// @title IAggregator - Responsible for batching and submitting feed updates
/// @notice Aggregators collect signatures from nodes and submit them on-chain
interface INodesAggregator is ICommonErrors {
    /// @notice Schnorr signature data struct containing aggregated signature information
    /// @dev signers indexes array must be sorted in ascending order to prevent replay attacks
    /// @param signature The aggregated Schnorr signature
    /// @param commitment The commitment point used in the signature
    /// @param signers Array of signer indices that participated in the signature
    struct SchnorrSignature {
        bytes32 signature;
        address commitment;
        uint256[] signers; 
    }

    /// @notice Thrown when an address is not a registered node
    /// @param addr The address that is not a node
    error NotNode(address addr);

    /// @notice Thrown when attempting to add a node but the maximum number of nodes has been reached
    error MaxNodesReached();

    /// @notice Thrown when attempting to add a node that is already registered
    /// @param node The address of the node that is already registered
    error NodeAlreadyAdded(address node);

    /// @notice Thrown when the provided signature fails verification
    error InvalidSignature();

    /// @notice Thrown when the provided commitment point is invalid
    error InvalidCommitment();

    /// @notice Thrown when the signers array is not sorted in ascending order
    error InvalidSignersOrder();

    /// @notice Thrown when the number of signatures is less than the minimum required threshold
    /// @param numberSigners The number of signatures provided
    /// @param minSignatureThreshold The minimum number of signatures required
    error NotEnoughSignatures(uint256 numberSigners, uint256 minSignatureThreshold);

    /// @notice Thrown when the provided public key is invalid
    error InvalidPublicKey();

    /// @notice Thrown when a signer index is invalid (zero or out of bounds)
    /// @param index The invalid index
    error InvalidIndex(uint256 index);

    /// @notice Emitted when a new node is added to the set
    /// @param node The address of the new node
    /// @param index The index assigned to the new node
    /// @param pointer The storage pointer to the updated nodes array
    event LogNodeAdded(address indexed node, uint256 index, address pointer);

    /// @notice Emitted when a node is removed from the set
    /// @param node The address of the removed node
    /// @param oldIndex The previous index of the removed node
    /// @param pointer The storage pointer to the updated nodes array
    event LogNodeRemoved(address indexed node, uint256 oldIndex, address pointer);

    /// @notice Emitted when the minimum signatures threshold is updated
    /// @param newThreshold The new minimum number of signatures required
    event LogThresholdUpdated(uint256 newThreshold);

    /// @notice Verify a Schnorr signature
    /// @param message The message to verify
    /// @param schnorrData The Schnorr signature data
    /// @param minSignaturesThreshold The minimum number of signatures required
    function verifySignature(
        bytes32 message,
        SchnorrSignature calldata schnorrData,
        uint256 minSignaturesThreshold
    ) external view;

    /// @notice Register a new node in the aggregator group
    /// @param pubkey Public key of the node
    function registerNode(LibSecp256k1.Point memory pubkey) external;

    /// @notice Unregister a node
    /// @param node Address of the node to remove
    function unregisterNode(address node) external;

    /// @notice Check if a node is currently registered
    /// @param node Address of the node
    /// @return isActive Whether the node is active
    function isNode(address node) external view returns (bool isActive);

    /// @notice Get the total number of nodes in the aggregator group
    /// @return totalSigners The total number of nodes
    function getTotalSigners() external view returns (uint256 totalSigners);

    /// @notice Get the hash of the signer set
    /// @return hash The hash of the signer set
    function getSignerSetHash() external view returns (bytes32 hash);
}
