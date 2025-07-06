// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {IFeed} from "../interfaces/IFeed.sol";

/**
 * @title PricingHelper
 * @notice Helper library for calculating subscription prices
 */
library PricingHelper {
    uint256 public constant BASE_PRICE_PER_SECOND_SCALED = 11574074; //1e6 * SCALAR / 1 days;
    uint256 public constant FREQUENCY_COEFFICIENT = 4000;
    uint256 public constant SIGNERS_COEFFICIENT = 6000;
    uint256 public constant PERSONAL_FEED_PRICE_MULTIPLIER = 3;

    /// @notice Fixed point scalar for calculations (100%)
    uint256 public constant SCALAR = 1e6;

    function calculatePrice(uint256 frequency, uint256 signaturesRequired, IFeed.FeedType feedType) public pure returns (uint256 pricePerSecondScaled) {
        // Calculate frequency factor using natural logarithm approximation
        uint256 updatesPerDay = 1 days / frequency;
        uint256 frequencyFactor = _precisePow(
            updatesPerDay,
            FREQUENCY_COEFFICIENT,
            10000
        );

        // Calculate signers factor using power function
        // signersFactor = signers^(coefficient/10000)
        uint256 signersFactor = _precisePow(
            signaturesRequired,
            SIGNERS_COEFFICIENT,
            10000
        );

        // Calculate final price
        pricePerSecondScaled = (BASE_PRICE_PER_SECOND_SCALED *
            frequencyFactor *
            signersFactor) / (SCALAR * SCALAR);

        if (feedType == IFeed.FeedType.PERSONAL) {
            pricePerSecondScaled = pricePerSecondScaled * PERSONAL_FEED_PRICE_MULTIPLIER;
        }
    }

    function getPriceForTimespan(
        uint256 pricePerSecondScaled,
        uint256 timespan
    ) public pure returns (uint256 price) {
        return (pricePerSecondScaled * timespan) / SCALAR;
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
        if (x == 0) return 0;
        if (x == 1) return 0;

        // For x >= 2, use the mathematical approach: ln(x) = ln(2^k * m) = k*ln(2) + ln(m)
        // where k is the integer part of log2(x) and m is the mantissa in [1, 2)

        // Find k (integer part of log2(x))
        uint256 k = 0;
        uint256 temp = x;
        while (temp >= 2) {
            temp >>= 1;
            k++;
        }

        // Calculate mantissa: m = x / 2^k, scaled to maintain precision
        // We want m in range [1, 2), scaled by SCALAR for precision
        uint256 mantissa = (x * SCALAR) >> k; // This gives us m * SCALAR

        // Now calculate ln(mantissa) using Taylor series around 1
        // For mantissa in [1, 2), let u = mantissa - 1, then ln(1 + u) ≈ u - u²/2 + u³/3 - u⁴/4
        uint256 u = mantissa - SCALAR; // u = (mantissa - 1) * SCALAR

        if (u == 0) {
            // mantissa = 1, so ln(mantissa) = 0
            return (k * 693147); // k * ln(2) * 1e6
        }

        // Calculate Taylor series terms: u - u²/2 + u³/3 - u⁴/4 + u⁵/5
        uint256 u2 = (u * u) / SCALAR;
        uint256 u3 = (u2 * u) / SCALAR;
        uint256 u4 = (u3 * u) / SCALAR;
        uint256 u5 = (u4 * u) / SCALAR;

        // ln(mantissa) = u - u²/2 + u³/3 - u⁴/4 + u⁵/5
        uint256 lnMantissa = u - u2 / 2 + u3 / 3 - u4 / 4 + u5 / 5;

        // Final result: k * ln(2) + ln(mantissa)
        return (k * 693147) + lnMantissa;
    }

    function _expTaylor(uint256 x) internal pure returns (uint256) {
        // e^x ≈ 1 + x + x²/2! + x³/6
        uint256 x2 = (x * x) / SCALAR;
        uint256 x3 = (x2 * x) / SCALAR;

        return SCALAR + x + (x2 / 2) + (x3 / 6);
    }
}
