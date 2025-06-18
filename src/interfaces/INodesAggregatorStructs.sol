// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title INodesAggregatorStructs
/// @notice Structs for the NodesAggregator
interface INodesAggregatorStructs {
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
