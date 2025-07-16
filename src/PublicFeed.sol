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
contract PublicFeed is BaseFeed {
    using ERC165Checker for address;

    FeedType internal constant FEED_TYPE = FeedType.PUBLIC;

    uint256 internal immutable _frequency;
    uint256 internal immutable _signaturesRequired;

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

    function _setFeedConfig(uint256, uint256, string calldata) internal pure override {
        revert NotSupported();
    }

    function _setFrequency(uint256) internal pure override {
        revert NotSupported();
    }

    function _setSignaturesRequired(uint256) internal pure override {
        revert NotPersonalFeed();
    }

    // check if immutable is set, if not - use the one from storage
    function _getSignaturesRequired() internal view override returns (uint256 signaturesRequired) {
        signaturesRequired = _signaturesRequired;
    }

    function _getFrequency() internal view override returns (uint256 frequency) {
        frequency = _frequency;
    }

    function _getPricePerSecondScaled() internal view returns (uint256 pricePerSecondScaled) {
        pricePerSecondScaled = PricingHelper.calculatePrice(_frequency, _signaturesRequired, FEED_TYPE);
    }

}
