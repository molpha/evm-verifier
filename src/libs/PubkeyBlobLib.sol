// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.31;

import {LibSecp256k1} from "./LibSecp256k1.sol";

/// @title PubkeyBlobLib
/// @notice In-memory helpers for `abi.encode(LibSecp256k1.Point[])` key blobs.
/// @dev Blob layout, measured from the `bytes` length word:
///      `0x00` byte length | `0x20` ABI offset | `0x40` array length | `0x60..` packed `(x, y)` points.
///      Callers are responsible for bounds: every function assumes `index` is within the array.
library PubkeyBlobLib {
    uint256 private constant ARRAY_LENGTH_OFFSET = 0x40;
    uint256 private constant POINTS_HEAD_OFFSET = 0x60;
    uint256 private constant POINT_SIZE = 0x40;

    /// @dev Appends `signerPubKey` in place. The blob must be the most recent memory
    ///      allocation, since the new point is written into the words directly above it.
    function addPubkey(bytes memory pubKeys, LibSecp256k1.Point memory signerPubKey) internal pure {
        uint256 prevLength = getNodesLength(pubKeys);
        assembly ("memory-safe") {
            let newByteLength := add(mload(pubKeys), POINT_SIZE)
            mstore(pubKeys, newByteLength)
            mstore(add(pubKeys, ARRAY_LENGTH_OFFSET), add(prevLength, 1))

            // Claim the appended point's words before writing them.
            let allocEnd := add(add(pubKeys, 0x20), newByteLength)
            if gt(allocEnd, mload(0x40)) { mstore(0x40, allocEnd) }

            let newPointSlot := add(add(pubKeys, POINTS_HEAD_OFFSET), mul(prevLength, POINT_SIZE))
            mstore(newPointSlot, mload(signerPubKey))
            mstore(add(newPointSlot, 0x20), mload(add(signerPubKey, 0x20)))
        }
    }

    /// @dev Removes `index` in place by swapping the tail entry into the hole (swap-and-pop).
    ///      Reverts nothing: an empty blob would underflow, so callers must reject that first.
    /// @return orderChanged True when a tail entry moved, i.e. `index` was not the last one.
    function removePubkey(bytes memory pubKeys, uint256 index) internal pure returns (bool orderChanged) {
        assembly ("memory-safe") {
            let lengthSlot := add(pubKeys, ARRAY_LENGTH_OFFSET)
            let lastIndex := sub(mload(lengthSlot), 1)

            mstore(pubKeys, sub(mload(pubKeys), POINT_SIZE))
            mstore(lengthSlot, lastIndex)

            orderChanged := iszero(eq(index, lastIndex))
            if orderChanged {
                let pointsHead := add(pubKeys, POINTS_HEAD_OFFSET)
                let hole := add(pointsHead, mul(index, POINT_SIZE))
                let tail := add(pointsHead, mul(lastIndex, POINT_SIZE))

                mstore(hole, mload(tail))
                mstore(add(hole, 0x20), mload(add(tail, 0x20)))
            }
        }
    }

    function getNode(bytes memory pubKeys, uint256 index) internal pure returns (LibSecp256k1.Point memory signer) {
        assembly ("memory-safe") {
            let pointStart := add(add(pubKeys, POINTS_HEAD_OFFSET), mul(index, POINT_SIZE))
            mstore(signer, mload(pointStart))
            mstore(add(signer, 0x20), mload(add(pointStart, 0x20)))
        }
    }

    function getNodesLength(bytes memory pubKeys) internal pure returns (uint256 signersAmount) {
        assembly ("memory-safe") {
            signersAmount := mload(add(pubKeys, ARRAY_LENGTH_OFFSET))
        }
    }
}
