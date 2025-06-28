// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

/// @title ISubscriptionPriceManager
/// @notice Interface for calculating feed subscription prices based on feed parameters
interface ISubscriptionPriceManager {
    // Events
    event PriceParametersUpdated(
        uint256 basePrice,
        uint256 frequencyCoefficient,
        uint256 signersCoefficient
    );
    event CustomPriceSet(address indexed feed, uint256 price);
    event CustomPriceRemoved(address indexed feed);

    // Errors
    error InvalidParameters();
    error PriceTooLow();
    error PriceTooHigh();
    error InvalidFeed();

    /// @notice Calculate subscription price for a feed
    /// @param frequency number of seconds between updates
    /// @param requiredSignatures Number of signatures required
    /// @return pricePerSecond Price in tokens per second
    function calculatePrice(
        uint256 frequency,
        uint256 requiredSignatures
    ) external view returns (uint256 pricePerSecond);

    /// @notice Update pricing parameters
    /// @param basePrice Base price for 1 update/day with 1 signer
    /// @param frequencyCoefficient Coefficient for frequency scaling (in basis points)
    /// @param signersCoefficient Coefficient for signers scaling (in basis points)
    function updatePriceParameters(
        uint256 basePrice,
        uint256 frequencyCoefficient,
        uint256 signersCoefficient
    ) external;

    /// @notice Get current pricing parameters
    /// @return basePrice Base price for 1 update/day with 1 signer
    /// @return frequencyCoefficient Coefficient for frequency scaling
    /// @return signersCoefficient Coefficient for signers scaling
    function getPriceParameters() external view returns (
        uint256 basePrice,
        uint256 frequencyCoefficient,
        uint256 signersCoefficient
    );
} 