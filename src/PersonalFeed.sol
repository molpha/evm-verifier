// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {ERC165Checker} from "./libs/ERC165Checker.sol";

import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {IFeed} from "./interfaces/IFeed.sol";
import {ISubscriptionRegistry} from "./interfaces/ISubscriptionRegistry.sol";
import {INodeRegistry} from "./interfaces/INodeRegistry.sol";
import {IFeed} from "./interfaces/IFeed.sol";
import {PricingHelper} from "./libs/PricingHelper.sol";
import {BaseFeed} from "./BaseFeed.sol";

// TODO: think about aggregator deactivation flow
contract PersonalFeed is BaseFeed {
    using ERC165Checker for address;

    FeedType internal constant FEED_TYPE = FeedType.PERSONAL;

    uint256 internal _frequency;
    uint256 internal _signaturesRequired;

  constructor(
        address accessControlManager,
        address subscriptionRegistry,
        address owner, 
        uint256 frequency, 
        uint256 signaturesRequired, 
        string memory ipfsCID
    ) BaseFeed(owner, accessControlManager, subscriptionRegistry, FEED_TYPE) {
        require(frequency > MIN_FREQUENCY && frequency <= MAX_FREQUENCY, InvalidFrequency(frequency));
        require(signaturesRequired > 0, InvalidMinSignaturesThreshold(signaturesRequired));
        require(keccak256(bytes(ipfsCID)) != keccak256(bytes("")), InvalidCID(ipfsCID));

        _frequency = frequency;
        _signaturesRequired = signaturesRequired;
        _ipfsCID = ipfsCID;
        _pricePerSecondScaled = PricingHelper.calculatePrice(frequency, signaturesRequired, FEED_TYPE);
    }

    function _setFeedConfig(uint256 frequency, uint256 signaturesRequired, string calldata ipfsCID) internal override {
        require(frequency >= MIN_FREQUENCY && frequency <= MAX_FREQUENCY, InvalidFrequency(frequency));
        require(signaturesRequired > 0, InvalidMinSignaturesThreshold(signaturesRequired));
        require(keccak256(bytes(ipfsCID)) != keccak256(bytes("")), InvalidCID(ipfsCID));

        uint256 pricePerSecondScaled = PricingHelper.calculatePrice(
            frequency,
            signaturesRequired,
            _feedType
        );

        _frequency = frequency;
        _signaturesRequired = signaturesRequired;
        _pricePerSecondScaled = pricePerSecondScaled;
        _ipfsCID = ipfsCID;

        emit LogFeedConfigChanged(
            frequency,
            signaturesRequired,
            pricePerSecondScaled,
            ipfsCID
        );
    }

    function _setFrequency(uint256 frequency) internal override {
        require(
            frequency >= MIN_FREQUENCY && frequency <= MAX_FREQUENCY,
            InvalidFrequency(frequency)
        );

        uint256 newPrice = PricingHelper.calculatePrice(
            frequency,
            _getSignaturesRequired(),
            FEED_TYPE
        );

        _pricePerSecondScaled = newPrice;
        _frequency = frequency;

        emit LogFrequencyChanged(frequency, newPrice);
    }

    function _setSignaturesRequired(
        uint256 signaturesRequired
    ) internal override {
        // TODO: add max signaturesRequired -> total amout of registered nodes
        require(
            signaturesRequired > 0,
            InvalidMinSignaturesThreshold(signaturesRequired)
        );

        uint256 newPrice = PricingHelper.calculatePrice(
            _getFrequency(),
            signaturesRequired,
            FEED_TYPE
        );

        _pricePerSecondScaled = newPrice;
        _signaturesRequired = signaturesRequired;

        emit LogMinSignaturesThresholdChanged(signaturesRequired, newPrice);
    }

    function _getSignaturesRequired()
        internal
        view
        override
        returns (uint256 signaturesRequired)
    {
        signaturesRequired = _signaturesRequired;
    }

    function _getFrequency()
        internal
        view
        override
        returns (uint256 frequency)
    {
        frequency = _frequency;
    }
}
