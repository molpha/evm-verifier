// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

// import {IFeed} from "molpha-oracle/interfaces/IFeed.sol";
// import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";

// contract ConsumerExample {
//     IFeed public immutable feed;

//     constructor(address _feed) {
//         feed = IFeed(_feed);
//     }

//     function getLatest()
//         external
//         view
//         returns (bytes memory value, uint256 timestamp)
//     {
//         return feed.getLatest();
//     }
             
//   function getLatestRoundData()
//         external
//         view
//         returns (
//             uint80 roundId,
//             int256 answer,
//             uint256 startedAt,
//             uint256 updatedAt,
//             uint80 answeredInRound
//         )
//     {
//         return AggregatorV3Interface(address(feed)).latestRoundData();
//     }
// }

//     /// @notice Get round data for a specific round ID using Chainlink AggregatorV3Interface
//     /// @param _roundId The round ID to get data for
//     /// @return roundId The round ID
//     /// @return answer The answer as int256 for the given round
//     /// @return startedAt The timestamp when the round started
//     /// @return updatedAt The timestamp when the round was updated
//     /// @return answeredInRound The round ID in which the answer was computed
//     /// @dev This uses Chainlink's standard interface for compatibility with existing Chainlink integrations
//     function getRoundData(
//         uint80 _roundId
//     )
//         external
//         view
//         returns (
//             uint80 roundId,
//             int256 answer,
//             uint256 startedAt,
//             uint256 updatedAt,
//             uint80 answeredInRound
//         )
//     {
//         return AggregatorV2V3Interface(address(feed)).getRoundData(_roundId);
//     }

//     /// @notice Get the latest answer as int256 (Chainlink-compatible)
//     /// @return answer The latest answer as int256
//     /// @dev Convenience function for simple price queries
//     function getLatestAnswer() external view returns (int256 answer) {
//         return AggregatorV2V3Interface(address(feed)).latestAnswer();
//     }

//     /// @notice Get the timestamp of the latest answer (Chainlink-compatible)
//     /// @return timestamp The timestamp of the latest answer
//     /// @dev Convenience function for checking data freshness
//     function getLatestTimestamp() external view returns (uint256 timestamp) {
//         return AggregatorV2V3Interface(address(feed)).latestTimestamp();
//     }

//     /// @notice Get the latest round ID (Chainlink-compatible)
//     /// @return roundId The latest round ID
//     /// @dev Use this to determine how many rounds of data are available
//     function getLatestRound() external view returns (uint256 roundId) {
//         return AggregatorV2V3Interface(address(feed)).latestRound();
//     }

//     /// @notice Internal helper function to decode bytes to uint256
//     /// @param data The bytes data to decode
//     /// @return value The decoded uint256 value
//     /// @dev Uses assembly for efficient decoding, requires at least 32 bytes
//     function _decodeUint256(
//         bytes memory data
//     ) internal pure returns (uint256 value) {
//         if (data.length < 32) revert InvalidDataLength();
//         assembly {
//             value := mload(add(data, 32))
//         }
//     }
// }
