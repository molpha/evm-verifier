// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {ICommonErrors} from "./ICommonErrors.sol";

/// @title INodeAggregatorErrors
/// @notice Errors for the NodeAggregator
interface INodeAggregatorErrors is ICommonErrors {
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
}
