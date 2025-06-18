// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {LibSecp256k1} from "./LibSecp256k1.sol";

/// @title SchnorrSetVerifierLib
/// @notice Library for managing a set of Schnorr public keys
/// @dev This library provides functions to add, remove, and retrieve Schnorr public keys from a bytes array
library SchnorrSetVerifierLib {
    /// @notice Adds a new signer's public key to the set
    /// @param pubKeys The bytes array containing all public keys
    /// @param signerPubKey The public key to add
    /// @dev The pubKeys parameter must be a bytes array with the following structure:
    ///      - First 32 bytes: total length of the bytes array
    ///      - Next 32 bytes: number of public keys
    ///      - Remaining bytes: concatenated public keys (each 64 bytes)
    function addNode(bytes memory pubKeys, LibSecp256k1.Point memory signerPubKey) internal pure {
        uint256 nodesAmount = getNodesLength(pubKeys);
         assembly {
            let newLength := add(nodesAmount, 1)
            let newBlocksLength := mul(newLength, 2)
            let lengthBlock := add(pubKeys, 0x40)
            let newItemBlock1 := sub(add(lengthBlock, mul(newBlocksLength, 0x20)), 0x20)
          
            // resize
            mstore(0x40, add(mload(0x40), 0x40)) // update free memory pointer
            mstore(pubKeys, add(mload(pubKeys), 0x40)) // increase bytes length
            mstore(lengthBlock, newLength) // increase array length

            // write new item
            mstore(newItemBlock1, mload(signerPubKey))
            mstore(add(newItemBlock1, 0x20), mload(add(signerPubKey, 0x20)))
        }
    }

    /// @notice Removes a signer's public key from the set
    /// @param pubKeys The bytes array containing all public keys
    /// @param index The index of the public key to remove
    /// @return orderChanged True if the order of remaining keys was changed, false if the last key was removed
    /// @dev If the removed key is not the last one, the last key is moved to the removed key's position
    function removeNode(bytes memory pubKeys, uint256 index) internal pure returns (bool orderChanged) {
        assembly {
            let length := sub(mload(add(pubKeys, 0x40)), 1)
            let lengthBlock := add(pubKeys, 0x40)

            let lastSigner := eq(index, length)
            orderChanged := not(lastSigner)

            // resize
            mstore(pubKeys, sub(mload(pubKeys), 0x40)) // decrease bytes length
            mstore(lengthBlock, length) // decrease array length

            // move last element to the index of removed element if it's not the last element
            if not(lastSigner) {
                let indexBlock1 := add(add(lengthBlock, mul(index, 0x40)), 0x20)
                let lastItemBlock1 := add(add(lengthBlock, mul(length, 0x40)), 0x20)

                mstore(indexBlock1, mload(lastItemBlock1))
                mstore(add(indexBlock1, 0x20), mload(add(lastItemBlock1, 0x20)))
            }
        }
    }

    /// @notice Retrieves a signer's public key from the set
    /// @param pubKeys The bytes array containing all public keys
    /// @param index The index of the public key to retrieve
    /// @return signer The public key at the specified index
    /// @dev The returned point contains the x and y coordinates of the public key
    function getNode(bytes memory pubKeys, uint256 index) internal pure returns (LibSecp256k1.Point memory signer) {
        assembly {
            mstore(signer, mload(add(pubKeys, add(0x60, mul(index, 0x40)))))
            mstore(add(signer, 0x20), mload(add(pubKeys, add(0x80, mul(index, 0x40)))))
        }
        
    }

    /// @notice Gets the total number of signers in the set
    /// @param pubKeys The bytes array containing all public keys
    /// @return signersAmount The number of public keys in the set
    function getNodesLength(bytes memory pubKeys) internal pure returns (uint256 signersAmount) {
        assembly {
            signersAmount := mload(add(pubKeys, 0x40)) // load array length
        }
    }
}