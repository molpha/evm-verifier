// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.31;

/// @title IValidatorStructs
/// @notice Structs for the Validator
interface IValidatorStructs {
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

    // /// @notice Data update struct containing feed address, value and timestamp
    // /// @param feed The feed address
    // /// @param jobId The job ID
    // /// @param value The value to update
    // /// @param tsAndRound High 64 bits = timestamp, low 32 bits = round (see `PublishCalldataLib`)
    // struct DataUpdate {
    //     address feed;
    //     bytes32 jobId;
    //     bytes value;
    //     uint96 tsAndRound;
    // }

    struct DataUpdate {
        bytes32 jobId;
        uint32 registryVersion;
        uint32  signaturesRequired;
        bytes32 configHash;
        bytes32 value;
        uint64 canonicalTimestamp;
    }

    // struct SchnorrSignature {
    //     uint256 signersBitmap;
    //     bytes32 R_agg;
    //     bytes32 s_agg;
    // }
}
