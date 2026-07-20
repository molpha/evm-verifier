// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {LibSecp256k1} from "./LibSecp256k1.sol";

/// @title PubkeyBlobLib
/// @notice Library for managing encoded public key blobs
/// @dev Operates on `bytes` produced by `abi.encode(LibSecp256k1.Point[])`
library PubkeyBlobLib {
    uint256 private constant ARRAY_LENGTH_OFFSET = 0x40;
    uint256 private constant POINTS_HEAD_OFFSET = 0x60;
    uint256 private constant POINT_SIZE = 0x40;

    /// @notice Appends a node key and updates aggregate key (index 0) in one pass
    /// @param pubKeys The `abi.encode(LibSecp256k1.Point[])` blob
    /// @param signerPubKey New node key to append
    /// @param currAgg New aggregate key to write into index 0
    function addPubkeyWithAggregate(
        bytes memory pubKeys,
        LibSecp256k1.Point memory signerPubKey,
        LibSecp256k1.Point memory currAgg
    ) internal pure {
        uint256 prevLength = getNodesLength(pubKeys);
        assembly ("memory-safe") {
            let newLength := add(prevLength, 1)
            let lengthSlot := add(pubKeys, ARRAY_LENGTH_OFFSET)
            let firstPointSlot := add(pubKeys, POINTS_HEAD_OFFSET)
            let newPointSlot := add(firstPointSlot, mul(prevLength, POINT_SIZE))

            // resize bytes payload and update dynamic array length
            mstore(pubKeys, add(mload(pubKeys), POINT_SIZE))
            mstore(lengthSlot, newLength)

            // write current aggregate at index 0
            mstore(firstPointSlot, mload(currAgg))
            mstore(add(firstPointSlot, 0x20), mload(add(currAgg, 0x20)))

            // append new node key at tail
            mstore(newPointSlot, mload(signerPubKey))
            mstore(add(newPointSlot, 0x20), mload(add(signerPubKey, 0x20)))

            // keep free memory pointer ahead of the grown blob
            let required := add(add(pubKeys, 0x20), mload(pubKeys))
            if gt(required, mload(0x40)) {
                mstore(0x40, required)
            }
        }
    }

    /// @notice Removes a public key from the set
    /// @param pubKeys The `abi.encode(LibSecp256k1.Point[])` blob
    /// @param index The index of the public key to remove
    /// @return orderChanged True if the order of remaining keys was changed, false if the last key was removed
    /// @dev If the removed key is not the last one, the last key is moved to the removed key's position
    function removePubkey(bytes memory pubKeys, uint256 index) internal pure returns (bool orderChanged) {
        assembly ("memory-safe") {
            let lengthSlot := add(pubKeys, ARRAY_LENGTH_OFFSET)
            let length := sub(mload(lengthSlot), 1)

            let lastSigner := eq(index, length)
            orderChanged := not(lastSigner)

            // resize
            mstore(pubKeys, sub(mload(pubKeys), POINT_SIZE)) // decrease bytes length
            mstore(lengthSlot, length) // decrease array length

            // move last element to the index of removed element if it's not the last element
            if not(lastSigner) {
                let pointsHead := add(pubKeys, POINTS_HEAD_OFFSET)
                let indexBlock1 := add(pointsHead, mul(index, POINT_SIZE))
                let lastItemBlock1 := add(pointsHead, mul(length, POINT_SIZE))

                mstore(indexBlock1, mload(lastItemBlock1))
                mstore(add(indexBlock1, 0x20), mload(add(lastItemBlock1, 0x20)))
            }
        }
    }

    /// @notice Updates aggregate at index 0 and removes a node in one pass
    /// @param pubKeys The `abi.encode(LibSecp256k1.Point[])` blob
    /// @param index Node index to remove (must be >= 1)
    /// @param currAgg New aggregate key to write into index 0
    /// @return orderChanged True if last node is swapped into removed index
    function removePubkeyWithAggregate(bytes memory pubKeys, uint256 index, LibSecp256k1.Point memory currAgg)
        internal
        pure
        returns (bool orderChanged)
    {
        setNode(pubKeys, 0, currAgg);
        orderChanged = removePubkey(pubKeys, index);
    }

    /// @notice Retrieves a signer's public key from the set
    /// @param pubKeys The `abi.encode(LibSecp256k1.Point[])` blob
    /// @param index The index of the public key to retrieve
    /// @return signer The public key at the specified index
    /// @dev The returned point contains the x and y coordinates of the public key
    function getNode(bytes memory pubKeys, uint256 index) internal pure returns (LibSecp256k1.Point memory signer) {
        assembly ("memory-safe") {
            let pointStart := add(add(pubKeys, POINTS_HEAD_OFFSET), mul(index, POINT_SIZE))
            mstore(signer, mload(pointStart))
            mstore(add(signer, 0x20), mload(add(pointStart, 0x20)))
        }
    }

    /// @notice Overwrites point at a given index
    /// @param pubKeys The `abi.encode(LibSecp256k1.Point[])` blob
    /// @param index Point index in the array
    /// @param signerPubKey Point value to write
    function setNode(bytes memory pubKeys, uint256 index, LibSecp256k1.Point memory signerPubKey) internal pure {
        assembly ("memory-safe") {
            let pointStart := add(add(pubKeys, POINTS_HEAD_OFFSET), mul(index, POINT_SIZE))
            mstore(pointStart, mload(signerPubKey))
            mstore(add(pointStart, 0x20), mload(add(signerPubKey, 0x20)))
        }
    }

    /// @notice Gets the total number of signers in the set
    /// @param pubKeys The `abi.encode(LibSecp256k1.Point[])` blob
    /// @return signersAmount The number of public keys in the set
    function getNodesLength(bytes memory pubKeys) internal pure returns (uint256 signersAmount) {
        assembly ("memory-safe") {
            signersAmount := mload(add(pubKeys, ARRAY_LENGTH_OFFSET))
        }
    }
}