// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.31;

/// @title NodeGroupBitmapLib
/// @notice Deterministic without-replacement node selection for a fixed registry size.
/// @dev PRF: `keccak256(seed || domain || counter)` with rejection sampling (limbs
///      `>= floor((2^32 - 1) / nCount) * nCount` are rejected); complements the mask when
///      `groupSize > nCount / 2`. Requires `nCount <= 256`.
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
        bytes32 domain = SELECTION_DOMAIN;
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, seed)
            mstore(add(ptr, 0x20), domain)

            let limit := mul(div(0xffffffff, nCount), nCount)
            let selected := 0
            let counter := 0

            for {} lt(selected, groupSize) {} {
                mstore(add(ptr, 0x40), counter)
                counter := add(counter, 1)
                let word := keccak256(ptr, 0x60)

                for { let w := 0 } and(lt(w, 8), lt(selected, groupSize)) { w := add(w, 1) } {
                    let limb := shr(224, word)
                    word := shl(32, word)
                    if lt(limb, limit) {
                        let bit := shl(mod(limb, nCount), 1)
                        if iszero(and(bitmap, bit)) {
                            bitmap := or(bitmap, bit)
                            selected := add(selected, 1)
                        }
                    }
                }
            }
        }
    }
}
