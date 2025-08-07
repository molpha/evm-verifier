// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title IPricingHelper
/// @notice Interface for the PricingManager contract
interface IPricingHelper {
    /// @notice Initialize the PricingHelper
    /// @param accessControlManager The access control manager address
    /// @param basePricePerSecondScaled The base price per second scaled
    /// @param frequencyCoefficient The frequency coefficient
    /// @param signersCoefficient The signers coefficient
    /// @param rewardPercentage The reward percentage
    function initialize(
        address accessControlManager,
        uint64 basePricePerSecondScaled, 
        uint64 frequencyCoefficient, 
        uint64 signersCoefficient, 
        uint64 rewardPercentage
    ) external;

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