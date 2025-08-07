// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {ERC165Checker} from "./libs/ERC165Checker.sol";
import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {IPricingHelper} from "./interfaces/IPricingHelper.sol";
import {IFeed} from "./interfaces/IFeed.sol";


/**
 * @title PricingHelper
 * @notice Contract for calculating subscription prices with configurable parameters
 */
contract PricingHelper is IPricingHelper, Initializable, ERC165 {
    using ERC165Checker for address;

    uint64 public constant MAX_BPS = 10000;

    uint64 internal _basePricePerSecondScaled ;
    uint64 internal _frequencyCoefficient;
    uint64 internal _signersCoefficient;
    uint64 internal _rewardPercentage;

    IAccessControlManager internal _accessControlManager;

    /// @notice Fixed point scalar for calculations (100%)
    uint256 public constant SCALAR = 1e6;

    modifier onlyProtocolAdmin() {
        _accessControlManager.verifyProtocolAdmin(msg.sender);
        _;
    }

    function initialize(
        address accessControlManager,
        uint64 basePricePerSecondScaled, 
        uint64 frequencyCoefficient, 
        uint64 signersCoefficient, 
        uint64 rewardPercentage
    ) public initializer {
        require(rewardPercentage <= MAX_BPS, "Reward percentage cannot exceed 100%");
        require(basePricePerSecondScaled > 0, "Base price per second scaled must be greater than 0");
        require(frequencyCoefficient > 0, "Frequency coefficient must be greater than 0");
        require(signersCoefficient > 0, "Signers coefficient must be greater than 0");

        accessControlManager.shouldSupport(type(IAccessControlManager).interfaceId);
        
        _accessControlManager = IAccessControlManager(accessControlManager);
        _basePricePerSecondScaled = basePricePerSecondScaled;
        _frequencyCoefficient = frequencyCoefficient;
        _signersCoefficient = signersCoefficient;
        _rewardPercentage = rewardPercentage;
    }

    function setBasePricePerSecondScaled(uint64 basePricePerSecondScaled) public onlyProtocolAdmin {
        _basePricePerSecondScaled = basePricePerSecondScaled;
    }

    function setFrequencyCoefficient(uint64 frequencyCoefficient) public onlyProtocolAdmin {
        _frequencyCoefficient = frequencyCoefficient;
    }

    function setSignersCoefficient(uint64 signersCoefficient) public onlyProtocolAdmin {
        _signersCoefficient = signersCoefficient;
    }

    function setRewardPercentage(uint64 rewardPercentage) public onlyProtocolAdmin {
        require(rewardPercentage <= MAX_BPS, "Reward percentage cannot exceed 100%");
        _rewardPercentage = rewardPercentage;
    }

    /**
     * @notice Calculate subscription price per second based on feed parameters
     * @dev Uses exponential scaling for frequency and signatures to reflect resource costs:
     *      - Higher frequency (more updates) increases cost exponentially
     *      - More required signatures increase cost exponentially
     *      - Personal feeds have additional multiplier
     * @param feed The feed address
     * @return pricePerSecondScaled Price per second scaled by SCALAR
     */
    function calculatePrice(address feed) public view returns (uint256 pricePerSecondScaled) {
        uint256 frequency = IFeed(feed).getFrequency();
        uint256 signaturesRequired = IFeed(feed).getMinSignaturesThreshold();

        // Calculate updates per day for frequency scaling
        uint256 updatesPerDay = 1 days / frequency;
        
        // Calculate frequency factor: updatesPerDay^(frequencyCoefficient/10000)
        // More frequent updates cost exponentially more due to increased load
        uint256 frequencyFactor = _precisePow(
            updatesPerDay,
            _frequencyCoefficient,
            10000
        );

        // Calculate signers factor: signaturesRequired^(signersCoefficient/10000)  
        // More signatures cost exponentially more due to increased coordination overhead
        uint256 signersFactor = _precisePow(
            signaturesRequired,
            _signersCoefficient,
            10000
        );

        // Calculate base price: basePricePerSecond * frequencyFactor * signersFactor
        // Division by (SCALAR * SCALAR) normalizes the result since both factors are SCALAR-scaled
        pricePerSecondScaled = (_basePricePerSecondScaled * frequencyFactor * signersFactor) / (SCALAR * SCALAR);
    }

    function getPriceForTimespan(
        uint256 pricePerSecondScaled,
        uint256 timespan
    ) public pure returns (uint256 price) {
        return (pricePerSecondScaled * timespan) / SCALAR;
    }

    /**
     * @notice Calculate reward price per answer for a node
     * @dev Calculates reward based on configurable percentage of subscription price,
     *      distributed among signer nodes per update frequency
     * @param feed The feed address
     * @return rewardPerAnswerScaled Reward per answer for a node, scaled by SCALAR
     */
    function getRewardPrice(address feed) public view returns (uint256 rewardPerAnswerScaled) {
        uint256 frequency = IFeed(feed).getFrequency();
        uint256 signaturesRequired = IFeed(feed).getMinSignaturesThreshold();

        require(frequency > 0, "Frequency must be greater than 0");
        require(signaturesRequired > 0, "Signatures required must be greater than 0");
        
        // Get the price per second scaled
        uint256 pricePerSecondScaled = calculatePrice(feed);
        
        // Mathematical simplification:
        // Daily reward pool = (pricePerSecond * 1 day) * rewardPercentage / 10000
        // Updates per day = 1 day / frequency
        // Reward per update = Daily reward pool / Updates per day
        // Reward per node per update = Reward per update / signaturesRequired
        // 
        // Simplified: rewardPerAnswerScaled = (pricePerSecond * frequency * rewardPercentage) / (signaturesRequired * 10000)
        rewardPerAnswerScaled = (pricePerSecondScaled * frequency * _rewardPercentage) / (signaturesRequired * 10000);
    }

    /**
     * @notice Get the current reward percentage
     * @return Reward percentage in basis points (e.g., 5000 = 50%)
     */
    function getRewardPercentage() public view returns (uint64) {
        return _rewardPercentage;
    }

    /**
     * @notice Get all pricing configuration parameters
     * @return basePricePerSecondScaled Base price per second scaled by SCALAR
     * @return frequencyCoefficient Coefficient for frequency scaling (basis points)
     * @return signersCoefficient Coefficient for signers scaling (basis points)  
     * @return rewardPercentage Reward percentage in basis points
     */
    function getPricingConfig() public view returns (
        uint64 basePricePerSecondScaled,
        uint64 frequencyCoefficient,
        uint64 signersCoefficient,
        uint64 rewardPercentage
    ) {
        return (
            _basePricePerSecondScaled,
            _frequencyCoefficient,
            _signersCoefficient,
            _rewardPercentage
        );
    }

    /**
     * @notice Get the access control manager address
     * @return Address of the access control manager
     */
    function getAccessControlManager() public view returns (IAccessControlManager) {
        return _accessControlManager;
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

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IPricingHelper).interfaceId || super.supportsInterface(interfaceId);
    }
}
