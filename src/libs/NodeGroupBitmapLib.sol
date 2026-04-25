// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.31;

/// @title NodeGroupBitmapLib
/// @notice Seeded, deterministic group bitmap: `keccak256(abi.encodePacked(seed, uint256(round), attempt)) % nCount`
///         for increasing `attempt` until `groupSize` unique indices are set.
library NodeGroupBitmapLib {
    /// @dev Bumps `freeMemoryPointer` by one `bytes(96)` scratch for the 3×32B hash preimage; cheaper than
    ///      rebuilding `abi.encodePacked` in the hot loop.
    function derive(bytes32 seed, uint32 round, uint256 nCount, uint256 groupSize)
        internal
        pure
        returns (uint256 bitmap)
    {
        if (groupSize > nCount) revert("groupSize exceeds nodeCount");
        if (groupSize == 0) return 0;
        if (groupSize == nCount) {
            if (nCount == 256) {
                return type(uint256).max;
            }
            return (uint256(1) << nCount) - 1;
        }
        uint256 roundWord = uint256(uint32(round));
        bytes memory scratch = new bytes(96);
        uint256 p;
        assembly ("memory-safe") {
            p := add(scratch, 0x20)
            mstore(p, seed)
            mstore(add(p, 0x20), roundWord)
        }
        uint256 selected;
        uint256 attempt;
        while (selected < groupSize) {
            uint256 h;
            assembly ("memory-safe") {
                mstore(add(p, 0x40), attempt)
                h := keccak256(p, 0x60)
            }
            uint256 pos = h % nCount;
            uint256 bit = uint256(1) << pos;
            if (bitmap & bit == 0) {
                bitmap |= bit;
                ++selected;
            }
            unchecked {
                ++attempt;
            }
        }
    }
}
