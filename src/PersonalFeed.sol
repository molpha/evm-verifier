// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {MessageHashUtils} from "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {IFeed} from "./interfaces/IFeed.sol";
import {ISubscriptionRegistry} from "./interfaces/ISubscriptionRegistry.sol";
import {INodeRegistry} from "./interfaces/INodeRegistry.sol";
import {IFeed} from "./interfaces/IFeed.sol";
import {PricingHelper} from "./libs/PricingHelper.sol";
import {BaseFeed} from "./BaseFeed.sol";

// TODO: think about aggregator deactivation flow
contract PersonalFeed is BaseFeed {
    using MessageHashUtils for bytes32;

    FeedType internal constant FEED_TYPE = FeedType.PERSONAL;

    uint256 internal _frequency;
    uint256 internal _signaturesRequired;

    modifier onlyFeedOwner() {
        require(msg.sender == _owner, NotFeedOwner(msg.sender));
        _;
    }

    constructor(
        IAccessControlManager accessControlManager,
        INodeRegistry nodeRegistry,
        ISubscriptionRegistry subscriptionRegistry,
        address owner,
        uint256 signaturesRequired, // must be 0 for public feeds; TODO: think about this and implement properly
        uint256 frequency,
        string memory ipfsCID
    )
        BaseFeed(
            accessControlManager,
            nodeRegistry,
            subscriptionRegistry,
            owner
        )
    {
        _frequency = frequency;
        _signaturesRequired = signaturesRequired;
        _ipfsCID = ipfsCID;
        _pricePerSecondScaled = PricingHelper.calculatePrice(
            frequency,
            signaturesRequired,
            FEED_TYPE
        );
    }

    function _setFeedConfig(
        uint256 frequency,
        uint256 signaturesRequired,
        string calldata ipfsCID
    ) internal override onlyFeedOwner {
        require(
            frequency >= MIN_FREQUENCY && frequency <= MAX_FREQUENCY,
            InvalidFrequency(frequency)
        );
        // TODO: add max minSignaturesThreshol`d -> total amout of registered nodes
        require(
            signaturesRequired > 0,
            InvalidMinSignaturesThreshold(signaturesRequired)
        );
        require(
            keccak256(bytes(ipfsCID)) != keccak256(bytes("")),
            InvalidCID(ipfsCID)
        );

        uint256 pricePerSecondScaled = PricingHelper.calculatePrice(
            frequency,
            signaturesRequired,
            FEED_TYPE
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

    function _setFrequency(uint256 frequency) internal override onlyFeedOwner {
        require(
            frequency >= MIN_FREQUENCY && frequency <= MAX_FREQUENCY,
            InvalidFrequency(frequency)
        );

        uint256 newPrice = PricingHelper.calculatePrice(
            frequency,
            _getMinSignaturesThreshold(),
            FEED_TYPE
        );

        _pricePerSecondScaled = newPrice;
        _frequency = frequency;

        emit LogFrequencyChanged(frequency, newPrice);
    }

    function _setMinSignaturesThreshold(
        uint256 signaturesRequired
    ) internal override onlyFeedOwner {
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

    function _setCID(string calldata cid) internal override onlyFeedOwner {
        require(keccak256(bytes(cid)) != keccak256(bytes("")), InvalidCID(cid));

        _ipfsCID = cid;
        emit LogCIDChanged(cid);
    }

    function _checkAccess(
        address consumer
    ) internal view override returns (bool hasAccess) {
        hasAccess =
            _subscriptionRegistry.isSubscribed(_owner, address(this)) &&
            _subscriptionRegistry.isSubscribed(consumer, address(this));
    }

    function _getFeedType() internal pure override returns (FeedType feedType) {
        feedType = FEED_TYPE;
    }

    function _getMinSignaturesThreshold()
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

    function _getPricePerSecondScaled()
        internal
        view
        override
        returns (uint256 pricePerSecondScaled)
    {
        pricePerSecondScaled = _pricePerSecondScaled;
    }
}
