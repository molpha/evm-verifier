// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

// import {IFeedsFactoryEvents} from "./IFeedsFactoryEvents.sol";

/// @title Aggregator factory interface
/// @notice Defines all external methods and events of AggregatorFactory contract
/// IAgregatorFactory is a contract responsible for creating new Aggregator contracts
/// deployed using transparent proxy pattern
interface IFeedsFactory /*is IFeedsFactoryEvents*/ {
    /// @notice build new Aggregator contract
    /// @dev can be called only by aggregator registry
    function build() external returns (address);

    /// @notice set new implementation address
    /// @dev can be called only by protocol admin
    /// @param implementation Aggregator implementation address
    function setAggregatorImpl(address implementation) external;

    /// @notice returns aggregator implementation address
    /// @return aggregator implementation address
    function getAggregatorImpl() external view returns (address);
}
