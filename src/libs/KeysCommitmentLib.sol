// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.31;

import {PubkeyBlobLib} from "./PubkeyBlobLib.sol";

/// @title KeysCommitmentLib
/// @notice Encoding-free commitment over raw secp256k1 coordinates in blob order.
/// @dev Hashes contiguous 64-byte (x || y) big-endian pairs starting at the first
///      Point in an `abi.encode(Point[])` blob — no ABI offset/length framing.
library KeysCommitmentLib {
    using PubkeyBlobLib for bytes;

    /// @dev Memory offset from `bytes` length word to the first Point: 0x20 (data start)
    ///      + 0x20 (ABI offset) + 0x20 (array length) = 0x60.
    uint256 private constant POINTS_HEAD_OFFSET = 0x60;

    function emptyCommitment() internal pure returns (bytes32) {
        return keccak256("");
    }

    function commitment(bytes memory keysBlob) internal pure returns (bytes32 hash) {
        uint256 nodeCount = keysBlob.getNodesLength();
        if (nodeCount == 0) return emptyCommitment();

        assembly ("memory-safe") {
            hash := keccak256(add(keysBlob, POINTS_HEAD_OFFSET), mul(nodeCount, 64))
        }
    }
}
