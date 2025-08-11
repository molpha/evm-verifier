// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title INodeRegistryStructs
/// @notice Structs for the NodeRegistry
interface INodeRegistryStructs {
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

    /// @notice Data update struct containing feed address, value and timestamp
    /// @param feed The feed address
    /// @param value The value to update
    /// @param timestamp The timestamp of the update
    struct DataUpdate {
        address feed;
        bytes32 feedId;
        bytes value;
        uint64 timestamp;
    }
}
