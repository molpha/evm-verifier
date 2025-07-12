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
contract PublicFeed is BaseFeed {
    using MessageHashUtils for bytes32;

    FeedType internal constant FEED_TYPE = FeedType.PUBLIC;

    uint256 internal immutable _frequency;
    uint256 internal immutable _signaturesRequired;

    constructor(
        IAccessControlManager accessControlManager,
        INodeRegistry nodeRegistry,
        ISubscriptionRegistry subscriptionRegistry,
        address owner,
        uint256 signaturesRequired, // must be 0 for public feeds; TODO: think about this and implement properly
        uint256 frequency,
        string memory ipfsCID
    ) BaseFeed(
        accessControlManager,
        nodeRegistry,
        subscriptionRegistry,
        owner
    ) {

        _frequency = frequency;
        _signaturesRequired = signaturesRequired;
        _ipfsCID = ipfsCID;
        _pricePerSecondScaled = PricingHelper.calculatePrice(frequency, signaturesRequired, FEED_TYPE);
    }

    function _checkAccess(address consumer) internal view override returns (bool) {
        return _subscriptionRegistry.isSubscribed(consumer, address(this));
    }

    function _setFeedConfig(uint256, uint256, string calldata) internal pure override {
        revert NotSupported();
    }

    function _setFrequency(uint256) internal pure override {
        revert NotSupported();
    }

    function _setMinSignaturesThreshold(uint256) internal pure override {
        revert NotPersonalFeed();
    }

    function _setCID(string calldata) internal pure override {
        revert NotSupported();
    }

    function _getFeedType() internal pure override returns (FeedType feedType) {
        feedType = FEED_TYPE;
    }

    // check if immutable is set, if not - use the one from storage
    function _getMinSignaturesThreshold() internal view override returns (uint256 signaturesRequired) {
        signaturesRequired = _signaturesRequired;
    }

    function _getFrequency() internal view override returns (uint256 frequency) {
        frequency = _frequency;
    }

    function _getPricePerSecondScaled() internal view override returns (uint256 pricePerSecondScaled) {
        pricePerSecondScaled = PricingHelper.calculatePrice(_frequency, _signaturesRequired, FEED_TYPE);
    }

}
