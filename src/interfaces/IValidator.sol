// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.31;

import {LibSecp256k1} from "../libs/LibSecp256k1.sol";
import {IValidatorStructs} from "./IValidatorStructs.sol";
import {IValidatorEvents} from "./IValidatorEvents.sol";

/// @title IValidator
/// @notice Interface for the Validator
interface IValidator is IValidatorStructs, IValidatorEvents {
    /// @notice Initialize the validator
    function initialize() external;

    /// @notice Add a new node in the aggregator group
    /// @param compressedPubKey Compressed public key of the node
    /// @param pop Schnorr proof-of-possession by the same key over the registration domain message
    function addNode(bytes memory compressedPubKey, SchnorrProof calldata pop) external;

    /// @notice Remove a node from the aggregator group
    /// @param node Address of the node to remove
    function removeNode(address node) external;

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

    /// @notice Verify a Schnorr signature
    /// @param dataUpdate The data update
    /// @param schnorrData The Schnorr signature data
    /// @notice Reverts if verification fails. Not `view`: publish path records participation in the same pass.
    function verify(
        DataUpdate calldata dataUpdate,
        SchnorrSignature calldata schnorrData
    ) external view returns (bool);

    /// @notice Get the index of a node (alternative name for compatibility)
    /// @param node Address of the node
    /// @return index The index of the node
    function getNodeIndex(address node) external view returns (uint256 index);
}
