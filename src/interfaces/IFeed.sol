// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title IFeed - Interface for a data feed contract
/// @notice Handles feed metadata, update logic, and on-chain value access
/// @dev Implemented by specific feed contracts
interface IFeed {
    /// @notice Called by Aggregator contract to push a new update
    /// @param value New feed value (raw bytes)
    function pushUpdate(bytes calldata value) external;

    /// @notice Returns the latest feed data
    /// @return value The latest value
    /// @return timestamp Last update time
    /// @return updateCount Monotonic counter to prevent replays
    function latest() external view returns (
        bytes memory value,
        uint256 timestamp,
        uint256 updateCount
    );

    /// @notice Returns the last update timestamp
    /// @return timestamp UNIX timestamp of last update
    function lastUpdated() external view returns (uint256 timestamp);

    /// @notice Returns the entry at a specific index
    /// @param index The index of the entry
    /// @return value The value of the entry
    /// @return timestamp The timestamp of the entry
    function getEntry(uint256 index) external view returns (bytes memory value, uint256 timestamp);

    /// @notice Returns the total number of entries
    /// @return count The total number of entries
    function getCount() external view returns (uint256 count);

}
