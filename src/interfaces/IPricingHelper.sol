// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {IERC165} from "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

/// @title IPricingHelper
/// @notice Interface for the PricingManager contract
interface IPricingHelper is IERC165 {
    /// @notice Calculate the price per second scaled for a feed
    /// @param feed The feed address
    /// @return pricePerSecondScaled The price per second scaled
    function calculatePrice(address feed) external view returns (uint256 pricePerSecondScaled);

    /// @notice Get the price for a timespan
    /// @param pricePerSecondScaled The price per second scaled
    /// @param timespan The timespan
    /// @return price The price
    function getPriceForTimespan(uint256 pricePerSecondScaled, uint256 timespan) external pure returns (uint256 price);
}