// SPDX-License-Identifier: MIT

pragma solidity ^0.8.31;

library BitmapLib {
    /// @dev Hamming weight for 256 bits (parallel SWAR).
    function popCount(uint256 x) internal pure returns (uint256 c) {
        unchecked {
            x -=
                (x >> 1) &
                0x5555555555555555555555555555555555555555555555555555555555555555;
            x =
                (x &
                    0x3333333333333333333333333333333333333333333333333333333333333333) +
                ((x >> 2) &
                    0x3333333333333333333333333333333333333333333333333333333333333333);
            x =
                (x + (x >> 4)) &
                0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f;
            // 16-byte horizontal add per 128-bit lane (max sum 16 * 8 = 128)
            uint256 rep16 = 0x01010101010101010101010101010101;
            uint256 lo = x & ((uint256(1) << 128) - 1);
            uint256 hi = x >> 128;
            c = ((lo * rep16) >> 120) + ((hi * rep16) >> 120);
        }
    }

    /// @dev `x` must be a power of two (single set bit), e.g. from `b & (0 - b)` on nonzero `b`.
    ///      Uses EVM `CLZ` (Yul `clz`) on Osaka+; for 256 bits, `ctz(2^k) = 255 - clz(2^k)`.
    function ctzPow2(uint256 x) internal pure returns (uint256 r) {
        assembly ("memory-safe") {
            r := sub(255, clz(x))
        }
    }

    /// @dev Trailing zero count (index of lowest set bit). `x` must be nonzero.
    function ctz256(uint256 x) internal pure returns (uint256 r) {
        unchecked {
            if ((x & type(uint128).max) == 0) {
                r += 128;
                x >>= 128;
            }
            if ((x & type(uint64).max) == 0) {
                r += 64;
                x >>= 64;
            }
            if ((x & type(uint32).max) == 0) {
                r += 32;
                x >>= 32;
            }
            if ((x & type(uint16).max) == 0) {
                r += 16;
                x >>= 16;
            }
            if ((x & type(uint8).max) == 0) {
                r += 8;
                x >>= 8;
            }
            if ((x & 0xf) == 0) {
                r += 4;
                x >>= 4;
            }
            if ((x & 0x3) == 0) {
                r += 2;
                x >>= 2;
            }
            if ((x & 0x1) == 0) {
                ++r;
            }
        }
    }
}
