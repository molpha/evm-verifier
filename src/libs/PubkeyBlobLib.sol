// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.31;

import {LibSecp256k1} from "./LibSecp256k1.sol";

/// @title PubkeyBlobLib
/// @notice In-memory helpers for `abi.encode(LibSecp256k1.Point[])` key blobs.
/// @dev Blob layout, measured from the `bytes` length word:
///      `0x00` byte length | `0x20` ABI offset | `0x40` array length | `0x60..` packed `(x, y)` points.
///      Callers are responsible for bounds: every function assumes `index` is within the array.
///      A removed node leaves a hole, the zero point `(0, 0)`, which is no valid key.
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

    /// @dev Index of the lowest hole (a zero point), or the array length when there is none.
    function firstFreeSlot(bytes memory pubKeys) internal pure returns (uint256 slot) {
        uint256 length = getNodesLength(pubKeys);
        assembly ("memory-safe") {
            let head := add(pubKeys, POINTS_HEAD_OFFSET)
            for { slot := 0 } lt(slot, length) { slot := add(slot, 1) } {
                let at := add(head, mul(slot, POINT_SIZE))
                if iszero(or(mload(at), mload(add(at, 0x20)))) { break }
            }
        }
    }

    /// @dev Overwrites the point at `index`, which must be inside the array. Used to fill a hole.
    function setPubkey(bytes memory pubKeys, uint256 index, LibSecp256k1.Point memory signerPubKey) internal pure {
        assembly ("memory-safe") {
            let at := add(add(pubKeys, POINTS_HEAD_OFFSET), mul(index, POINT_SIZE))
            mstore(at, mload(signerPubKey))
            mstore(add(at, 0x20), mload(add(signerPubKey, 0x20)))
        }
    }

    /// @dev Removes `index` in place without moving any other entry: the point becomes a hole (the
    ///      zero point), then trailing holes are dropped so the array ends on a live point.
    ///      Callers must pass an `index` inside the array.
    /// @return newLength The array length after the removal.
    function clearPubkey(bytes memory pubKeys, uint256 index) internal pure returns (uint256 newLength) {
        assembly ("memory-safe") {
            let lengthSlot := add(pubKeys, ARRAY_LENGTH_OFFSET)
            let head := add(pubKeys, POINTS_HEAD_OFFSET)

            let hole := add(head, mul(index, POINT_SIZE))
            mstore(hole, 0)
            mstore(add(hole, 0x20), 0)

            newLength := mload(lengthSlot)
            for {} newLength {} {
                let last := add(head, mul(sub(newLength, 1), POINT_SIZE))
                if or(mload(last), mload(add(last, 0x20))) { break }
                newLength := sub(newLength, 1)
            }

            mstore(lengthSlot, newLength)
            mstore(pubKeys, add(ARRAY_LENGTH_OFFSET, mul(newLength, POINT_SIZE)))
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
