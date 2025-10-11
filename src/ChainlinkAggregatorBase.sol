// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";

import {ERC165Checker} from "./libs/ERC165Checker.sol";
import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {IFeed} from "./interfaces/IFeed.sol";
import {AggregatorV2V3Interface} from "./interfaces/chainlink/AggregatorV2V3Interface.sol";

// TODO: think about aggregator deactivation flow
abstract contract ChainlinkAggregatorBase is AggregatorV2V3Interface {
    function decimals() external pure override returns (uint8) {
        return 0;
    }

    function description() external pure override returns (string memory) {
        return "";
    }

    function version() external pure override returns (uint256) {
        return 0;
    }

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (int256 answer, uint256 timestamp) = _getInt256Answer(_roundId);

        return (
            _roundId,
            answer,
            timestamp, // startedAt = updatedAt for simplicity
            timestamp, // updatedAt
            _roundId // answeredInRound = roundId for simplicity
        );
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (int256 answer, uint256 timestamp, uint80 roundId) = _getLatestInt256Answer();

        return (
            roundId,
            answer,
            timestamp, // startedAt = updatedAt for simplicity
            timestamp, // updatedAt
            roundId // answeredInRound = roundId for simplicity
        );
    }

    function latestAnswer() external view override returns (int256) {
        (int256 answer,,) = _getLatestInt256Answer();
        return answer;
    }

    function latestTimestamp() external view returns (uint256) {
        (,uint256 timestamp,) = _getLatestInt256Answer();
        return timestamp;
    }

    function latestRound() external view returns (uint256) {
        (,uint256 timestamp,) = _getLatestInt256Answer();
        return timestamp;
    }

    function getAnswer(uint256 roundId) external view returns (int256) {
        (int256 answer,) = _getInt256Answer(roundId);
        return answer;
    }

    function getTimestamp(uint256 roundId) external view returns (uint256) {
        (,uint256 timestamp) = _getInt256Answer(roundId);
        return timestamp;
    }

    /// Private functions

    /// to support chainlonk interface we need to return int256
    /// if data doesn't fit in int256, we revert
    function _getInt256Answer(uint256 roundId) internal virtual view returns (int256 answer, uint256 ts);
    function _getLatestInt256Answer() internal virtual view returns (int256 answer, uint256 ts, uint80 roundId);
}
