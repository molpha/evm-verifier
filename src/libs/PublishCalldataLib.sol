// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.31;

/// @title PublishCalldataLib
/// @notice Helpers for packed `DataUpdate.tsAndRound` (saves one 32-byte ABI head word vs separate `uint64` + `uint32`).
library PublishCalldataLib {
    /// @dev High 64 bits = `timestamp`, low 32 bits = `round`.
    function packTsRound(uint64 timestamp, uint32 round) internal pure returns (uint96 packed) {
        packed = uint96((uint256(timestamp) << 32) | uint256(round));
    }

    function unpackTimestamp(uint96 packed) internal pure returns (uint64 timestamp) {
        timestamp = uint64(uint256(packed) >> 32);
    }

    function unpackRound(uint96 packed) internal pure returns (uint32 round) {
        round = uint32(uint256(packed));
    }
}
