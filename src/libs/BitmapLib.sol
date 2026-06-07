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
    ///      Portable across pre-Osaka EVMs (no `clz` opcode dependency).
    function ctzPow2(uint256 x) internal pure returns (uint256 r) {
        unchecked {
            if (x & type(uint128).max == 0) {
                x >>= 128;
                r += 128;
            }
            if (x & type(uint64).max == 0) {
                x >>= 64;
                r += 64;
            }
            if (x & type(uint32).max == 0) {
                x >>= 32;
                r += 32;
            }
            if (x & type(uint16).max == 0) {
                x >>= 16;
                r += 16;
            }
            if (x & type(uint8).max == 0) {
                x >>= 8;
                r += 8;
            }
            if (x & 0x0f == 0) {
                x >>= 4;
                r += 4;
            }
            if (x & 0x03 == 0) {
                x >>= 2;
                r += 2;
            }
            if (x & 0x01 == 0) {
                r += 1;
            }
        }
    }

}
