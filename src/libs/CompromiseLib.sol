// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.31;

import {LibBit} from "solady/utils/LibBit.sol";

/// @title CompromiseLib
/// @notice Bitmap helpers for compromised-signer tracking (0-based bit ↔ blob index).
library CompromiseLib {
    using LibBit for uint256;

    function setBit(uint256 bitmap, uint256 index) internal pure returns (uint256) {
        return bitmap | (uint256(1) << index);
    }

    function clearBit(uint256 bitmap, uint256 index) internal pure returns (uint256) {
        return bitmap & ~(uint256(1) << index);
    }

    /// @dev Swap-and-pop bit permutation when removing blob index `removedIndex`
    ///      from a set of length `nodeCount` (before removal).
    function permuteOnRemove(uint256 bitmap, uint256 removedIndex, uint256 nodeCount) internal pure returns (uint256) {
        if (nodeCount == 0) return 0;
        uint256 last = nodeCount - 1;
        bitmap = clearBit(bitmap, removedIndex);
        if (removedIndex != last && (bitmap & (uint256(1) << last)) != 0) {
            bitmap = setBit(bitmap, removedIndex);
            bitmap = clearBit(bitmap, last);
        }
        return bitmap;
    }

    function effectiveSignerCount(uint256 signersBitmap, uint256 compromisedBitmap) internal pure returns (uint256) {
        return (signersBitmap & ~compromisedBitmap).popCount();
    }
}
