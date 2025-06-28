// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {ISubscriptionPriceManager} from "./interfaces/ISubscriptionPriceManager.sol";

/**
 * @title SubscriptionPriceManager
 * @notice Calculates feed subscription prices based on update frequency and signature requirements
 * @dev Uses non-linear scaling to prevent excessive prices for high-frequency feeds
 */
contract SubscriptionPriceManager is ISubscriptionPriceManager {
    /// @notice Fixed point scalar for calculations (100%)
    uint256 private constant SCALAR = 1e6;

    /// @notice Minimum price per second (in token units with 6 decimals)
    uint256 private constant MIN_PRICE_PER_DAY = 1e6;

    /// @notice Maximum price per second (in token units with 6 decimals)
    uint256 private constant MAX_PRICE_PER_DAY = 25e6;

    /// @notice Seconds in a year for conversion
    uint256 private constant SECONDS_PER_YEAR = 365 days;

    /// @notice Access control manager
    IAccessControlManager public immutable accessControlManager;

    /// @notice Base price for 1 update/day with 1 signer (per second)
    uint256 public basePricePerDay;

    /// @notice Coefficient for frequency scaling (in basis points, 10000 = 1.0)
    uint256 public frequencyCoefficient;

    /// @notice Coefficient for signers scaling (in basis points, 10000 = 1.0)
    uint256 public signersCoefficient;

    constructor(IAccessControlManager _accessControlManager) {
        accessControlManager = _accessControlManager;
        basePricePerDay = MIN_PRICE_PER_DAY;
        frequencyCoefficient = 5000;
        signersCoefficient = 5000;
    }

    /// @inheritdoc ISubscriptionPriceManager
    function calculatePrice(
        uint256 frequency,
        uint256 requiredSignatures
    ) public view returns (uint256 pricePerDay) {
        if (frequency == 0 || requiredSignatures == 0)
            revert InvalidParameters();

        // Calculate frequency factor using natural logarithm approximation
        uint256 updatesPerDay = 1 days / frequency;
        uint256 frequencyFactor = _precisePow(
            updatesPerDay,
            frequencyCoefficient,
            10000
        );

        // Calculate signers factor using power function
        // signersFactor = signers^(coefficient/10000)
        uint256 signersFactor = _precisePow(
            requiredSignatures,
            signersCoefficient,
            10000
        );

        // Calculate final price
        pricePerDay =
            (basePricePerDay * frequencyFactor * signersFactor) /
            (SCALAR * SCALAR);
    }

    /// @inheritdoc ISubscriptionPriceManager
    function updatePriceParameters(
        uint256 _basePricePerDay,
        uint256 _frequencyCoefficient,
        uint256 _signersCoefficient
    ) external {
        _validateParameters(
            _basePricePerDay,
            _frequencyCoefficient,
            _signersCoefficient
        );

        basePricePerDay = _basePricePerDay;
        frequencyCoefficient = _frequencyCoefficient;
        signersCoefficient = _signersCoefficient;

        emit PriceParametersUpdated(
            basePricePerDay,
            _frequencyCoefficient,
            _signersCoefficient
        );
    }

    /// @inheritdoc ISubscriptionPriceManager
    function getPriceParameters()
        external
        view
        returns (
            uint256 _basePrice,
            uint256 _frequencyCoefficient,
            uint256 _signersCoefficient
        )
    {
        return (basePricePerDay, frequencyCoefficient, signersCoefficient);
    }

    /// @notice Validate pricing parameters
    function _validateParameters(
        uint256 _basePrice,
        uint256 _frequencyCoefficient,
        uint256 _signersCoefficient
    ) private pure {
        // if (_basePrice < MIN_PRICE_PER_SECOND || _basePrice > MAX_PRICE_PER_SECOND) {
        //     revert InvalidParameters();
        // }
        if (_frequencyCoefficient == 0 || _frequencyCoefficient > 20000) {
            // Max 2.0
            revert InvalidParameters();
        }
        if (_signersCoefficient == 0 || _signersCoefficient > 20000) {
            // Max 2.0
            revert InvalidParameters();
        }
    }

    function _precisePow(
        uint256 x,
        uint256 n,
        uint256 d
    ) internal pure returns (uint256) {
        // Use logarithmic identity: x^a = e^(a * ln(x))
        // where a = n / d

        uint256 lnX = _preciseLn(x); // scaled by SCALAR
        uint256 expArg = (lnX * n) / d;

        return _expTaylor(expArg); // returns SCALAR-scaled result
    }

    function _preciseLn(uint256 x) internal pure returns (uint256) {
        // Use precomputed values for small x
        if (x == 1) return 0;
        if (x == 2) return 693147; // ln(2) * 1e6
        if (x == 3) return 1098612; // ln(3)
        if (x == 4) return 1386294; // ln(4)
        if (x == 5) return 1609438; // ln(5)
        if (x == 6) return 1785160;
        if (x == 7) return 1931471;
        if (x == 8) return 2079441;
        if (x == 9) return 2197225;
        if (x == 10) return 2302585;

        // fallback for large x
        return (693 * _log2(x)) / 1000;
    }

    function _expTaylor(uint256 x) internal pure returns (uint256) {
        // e^x ≈ 1 + x + x²/2! + x³/6
        uint256 x2 = (x * x) / SCALAR;
        uint256 x3 = (x2 * x) / SCALAR;

        return SCALAR + x + (x2 / 2) + (x3 / 6);
    }

    function _log2(uint256 x) internal pure returns (uint256 r) {
        require(x > 0, "log2(0) is undefined");
        while ((x >>= 1) != 0) {
            r++;
        }
        r *= SCALAR; // scale up like SCALAR
    }
}
