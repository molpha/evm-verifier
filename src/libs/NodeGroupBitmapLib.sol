// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/// @title NodeGroupBitmapLib
/// @notice Deterministic without-replacement node selection.
///
/// - PRF: `keccak256(seed || domain || counter)` — three 32-byte big-endian words (96 bytes);
///   `domain = keccak256("MOLPHA_SELECTION_DERIVE")` (`0x492848fe…b70b`), `counter` starts at 0.
/// - Each digest yields eight big-endian `uint32` limbs (MSB first).
/// - Unbiased index: reject `limb >= floor(2^32 / nCount) * nCount`, then `pos = limb % nCount`.
/// - Without replacement: skip positions already set in `bitmap`.
/// - If `groupSize > nCount / 2`, sample `nCount - groupSize` exclusions and complement the mask.
///
/// Requires `nCount <= 256` (result fits in one `uint256` bitmap).
library NodeGroupBitmapLib {
    error GroupSizeExceedsNodeCount();
    error NodeCountExceedsMax();
    error ZeroNodeCount();

    bytes32 internal constant SELECTION_DOMAIN = keccak256("MOLPHA_SELECTION_DERIVE");

    function derive(bytes32 seed, uint256 nCount, uint256 groupSize) internal pure returns (uint256 bitmap) {
        if (nCount == 0) revert ZeroNodeCount();
        if (nCount > 256) revert NodeCountExceedsMax();
        if (groupSize > nCount) revert GroupSizeExceedsNodeCount();
        if (groupSize == 0) return 0;
        if (groupSize == nCount) {
            return _fullMask(nCount);
        }

        if (groupSize > nCount / 2) {
            uint256 excluded = _sampleWithoutReplacement(seed, nCount, nCount - groupSize);
            unchecked {
                return _fullMask(nCount) ^ excluded;
            }
        }

        return _sampleWithoutReplacement(seed, nCount, groupSize);
    }

    function _fullMask(uint256 nCount) private pure returns (uint256 mask) {
        if (nCount == 256) {
            return type(uint256).max;
        }
        return (uint256(1) << nCount) - 1;
    }

    function _sampleWithoutReplacement(bytes32 seed, uint256 nCount, uint256 groupSize)
        private
        pure
        returns (uint256 bitmap)
    {
        uint256 limit = (uint256(type(uint32).max) / nCount) * nCount;
        uint256 selected;
        uint256 counter;
        while (selected < groupSize) {
            bytes32 digest = _hashRound(seed, counter);
            unchecked {
                ++counter;
            }
            uint256 word = uint256(digest);
            for (uint256 w; w < 8 && selected < groupSize;) {
                uint256 limb = word >> 224;
                word <<= 32;
                if (limb < limit) {
                    uint256 bit = uint256(1) << (limb % nCount);
                    if (bitmap & bit == 0) {
                        bitmap |= bit;
                        ++selected;
                    }
                }
                unchecked {
                    ++w;
                }
            }
        }
    }

    /// @dev `keccak256(seed || SELECTION_DOMAIN || counter)`; reuses `0x40` scratch (96-byte preimage).
    function _hashRound(bytes32 seed, uint256 counter) private pure returns (bytes32 digest) {
        bytes32 domain = SELECTION_DOMAIN;
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, seed)
            mstore(add(ptr, 0x20), domain)
            mstore(add(ptr, 0x40), counter)
            digest := keccak256(ptr, 0x60)
        }
    }
}
