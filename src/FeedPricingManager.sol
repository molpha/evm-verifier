// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";

/**
 * @title FeedPricingManager
 * @notice Calculates verifier rewards and subscription pricing for Molpha feeds
 */
contract FeedPricingManager {
    IAccessControlManager internal immutable _accessControlManager;

    // Configurable base constants (can be tuned by protocol owner)
    uint256 public baseSigPrice = 1e4; // $0.01 in USDC (6 decimals) → 0.01 * 1e6 = 10_000
    uint256 public baseUpdateInterval = 86400; // 24 hours (daily updates) as baseline

    struct FeedConfig {
        uint256 updateInterval;     // Seconds between updates (e.g. 300 for 5min updates)
        uint256 minSigners;         // e.g. 5
        uint256 incentiveBps;      // Multiplier in basis points (e.g. 12000 = 1.2x for incentivized feeds)
    }

    constructor(IAccessControlManager accessControlManager) {
        address(accessControlManager).shouldSupport(type(IAccessControlManager).interfaceId);

        _accessControlManager = accessControlManager;
    }

    modifier onlyPriceManager() {
        _accessControlManager.verifyPriceManager(msg.sender);
        _;
    }

    /// @notice Computes price per signature (USDC 6 decimals)
    function getPricePerSignature(FeedConfig memory config) public view returns (uint256) {
        // Scale linearly with signer count and complexity, but inversely with frequency
        uint256 base = baseSigPrice;

        // Adjust for frequency: higher freq (lower interval) = cheaper per sig
        uint256 freqFactor = (config.updateInterval * 1e6) / baseUpdateInterval;

        // Adjust for incentive (in BPS: 10000 = 1x)
        uint256 incentiveFactor = config.incentiveBps;

        // Final reward per signature
        return (base * config.minSigners * freqFactor * incentiveFactor) / (1e6 * 10000);
    }

    /// @notice Computes monthly subscription fee for a given feed config
    function getMonthlySubscriptionPrice(FeedConfig memory config) external view returns (uint256) {
        uint256 sigReward = getPricePerSignature(config);
        // Calculate total signatures in 30 days: (30 days * 24 hours * 3600 seconds) / updateInterval * minSigners
        uint256 totalSigs = (30 * 24 * 3600) / config.updateInterval * config.minSigners;

        return sigReward * totalSigs;
    }

    /// @notice Update base constants (by protocol admin)
    function setBaseSigPrice(uint256 _new) external onlyPriceManager {
        baseSigPrice = _new;
    }

    function setBaseUpdateInterval(uint256 _new) external onlyPriceManager {
        baseUpdateInterval = _new;
    }
}
