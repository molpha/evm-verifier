// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title INodeRegistryStructs
/// @notice Structs for the NodeRegistry
interface INodeRegistryStructs {
    /// @notice Schnorr signature data struct containing aggregated signature information
    /// @dev `signersBitmap` uses 0-based bit positions: bit (i-1) set iff 1-based signer index i signed.
    ///      At most 256 nodes; bits outside the active node count must be zero.
    /// @param signature The aggregated Schnorr signature
    /// @param commitment The commitment point used in the signature
    /// @param signersBitmap Bitmap of participating signer indices (1-based index i → bit i-1)
    struct SchnorrSignature {
        bytes32 signature;
        address commitment;
        bytes32 signersBitmap;
    }

    /// @notice Data update struct containing feed address, value and timestamp
    /// @param feed The feed address
    /// @param jobId The job ID
    /// @param value The value to update
    /// @param timestamp The timestamp of the update
    /// @param round The job round counter for this publish (must equal stored round + 1)
    struct DataUpdate {
        address feed;
        bytes32 jobId;
        bytes value;
        uint64 timestamp;
        uint32 round;
    }
}
