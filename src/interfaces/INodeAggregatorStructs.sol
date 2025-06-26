// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title INodeAggregatorStructs
/// @notice Structs for the NodeAggregator
interface INodeAggregatorStructs {
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
}
