// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";

import {ERC165Checker} from "./libs/ERC165Checker.sol";
import {Feed} from "./Feed.sol";
import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {IFeed} from "./interfaces/IFeed.sol";
import {IFeedRegistry} from "./interfaces/IFeedRegistry.sol";
import {INodeRegistry} from "./interfaces/INodeRegistry.sol";
import {ISubscriptionRegistry} from "./interfaces/ISubscriptionRegistry.sol";
import {PricingHelper} from "./libs/PricingHelper.sol";

contract FeedRegistry is IFeedRegistry, ERC165 {
    using ERC165Checker for address;

    uint256 internal constant MAX_FREQUENCY = 1 days;
    uint256 internal constant MIN_FREQUENCY = 1 minutes;

    IAccessControlManager internal immutable _accessControlManager;
    INodeRegistry internal immutable _nodeRegistry;
    ISubscriptionRegistry internal immutable _subscriptionRegistry;

    mapping(address => FeedConfig) internal _feedConfigs;

    constructor(
        IAccessControlManager accessControlManager,
        ISubscriptionRegistry subscriptionRegistry,
        INodeRegistry nodeRegistry
    ) {
        address(accessControlManager).shouldSupport(type(IAccessControlManager).interfaceId);
        address(subscriptionRegistry).shouldSupport(type(ISubscriptionRegistry).interfaceId);
        address(nodeRegistry).shouldSupport(type(INodeRegistry).interfaceId);

        _accessControlManager = accessControlManager;
        _subscriptionRegistry = subscriptionRegistry;
        _nodeRegistry = nodeRegistry;
    }

    modifier onlyFeedManager() {
       _accessControlManager.verifyFeedManager(msg.sender);
        _;
    }

    modifier onlyFeedOwner(address feed) {
        require(_feedConfigs[feed].owner == msg.sender, NotFeedOwner(feed));
        _;
    }
    // TODO: add fees collection
    /// @inheritdoc IFeedRegistry
    function createFeed(FeedType feedType, uint256 frequency, uint256 minSignaturesThreshold, string memory ipfsCID) external override onlyFeedManager {
        _validateFeedConfig(feedType, frequency, minSignaturesThreshold, ipfsCID);

        address feed = address(new Feed(
            feedType,
            _accessControlManager,
            _nodeRegistry,
            _subscriptionRegistry,
            minSignaturesThreshold
        ));

        _feedConfigs[feed] = FeedConfig({
            feedType: feedType,
            owner: msg.sender,
            ipfsCID: ipfsCID,
            frequency: frequency,
            minSignaturesThreshold: minSignaturesThreshold,
            pricePerSecondScaled: PricingHelper.calculatePrice(frequency, minSignaturesThreshold)
        });

        emit LogFeedCreated(feed, feedType, frequency, minSignaturesThreshold, ipfsCID);
    }

    /// @inheritdoc IFeedRegistry
    function updateFeedConfig(address feed, uint256 frequency, uint256 minSignaturesThreshold, string calldata ipfsCID) external override onlyFeedOwner(feed) {
        require(_feedConfigs[feed].feedType == FeedType.PERSONAL, NotPersonalFeed(feed));
        require(frequency >= MIN_FREQUENCY && frequency <= MAX_FREQUENCY, InvalidFrequency(frequency));
        // TODO: add max minSignaturesThreshold -> total amout of registered nodes
        require(minSignaturesThreshold > 0, InvalidMinSignaturesThreshold(minSignaturesThreshold));
        require(keccak256(bytes(ipfsCID)) != keccak256(bytes("")), InvalidCID(ipfsCID));
    
        IFeed(feed).setMinSignaturesThreshold(minSignaturesThreshold);
        uint256 pricePerSecondScaled = PricingHelper.calculatePrice(frequency, minSignaturesThreshold);

        _feedConfigs[feed].frequency = frequency;
        _feedConfigs[feed].minSignaturesThreshold = minSignaturesThreshold;
        _feedConfigs[feed].ipfsCID = ipfsCID;
        _feedConfigs[feed].pricePerSecondScaled = pricePerSecondScaled;

        emit LogFeedConfigChanged(feed, frequency, minSignaturesThreshold, pricePerSecondScaled, ipfsCID);
    }

    /// @inheritdoc IFeedRegistry
    function setFrequency(address feed, uint256 frequency) external override onlyFeedOwner(feed) {
        require(_feedConfigs[feed].feedType == FeedType.PERSONAL, NotPersonalFeed(feed));
        require(frequency >= MIN_FREQUENCY && frequency <= MAX_FREQUENCY, InvalidFrequency(frequency));

        uint256 pricePerSecondScaled = PricingHelper.calculatePrice(frequency, _feedConfigs[feed].minSignaturesThreshold);

        _feedConfigs[feed].frequency = frequency;
        _feedConfigs[feed].pricePerSecondScaled = pricePerSecondScaled;

        emit LogFrequencyChanged(feed, frequency, pricePerSecondScaled);
    }

    /// @inheritdoc IFeedRegistry
    function setMinSignaturesThreshold(address feed, uint256 minSignaturesThreshold) external override onlyFeedOwner(feed) {
        require(_feedConfigs[feed].feedType == FeedType.PERSONAL, NotPersonalFeed(feed));
        // TODO: add max minSignaturesThreshold -> total amout of registered nodes
        require(minSignaturesThreshold > 0, InvalidMinSignaturesThreshold(minSignaturesThreshold));

        IFeed(feed).setMinSignaturesThreshold(minSignaturesThreshold);
        _feedConfigs[feed].minSignaturesThreshold = minSignaturesThreshold;

        uint256 pricePerSecondScaled = PricingHelper.calculatePrice(_feedConfigs[feed].frequency, minSignaturesThreshold);
        _feedConfigs[feed].pricePerSecondScaled = pricePerSecondScaled;

        emit LogMinSignaturesThresholdChanged(feed, minSignaturesThreshold, pricePerSecondScaled);
    }

    /// @inheritdoc IFeedRegistry
    function setCID(address feed, string calldata ipfsCID) external override onlyFeedOwner(feed) {
        require(_feedConfigs[feed].feedType == FeedType.PERSONAL, NotPersonalFeed(feed));
        require(keccak256(bytes(ipfsCID)) != keccak256(bytes("")), InvalidCID(ipfsCID));

        _feedConfigs[feed].ipfsCID = ipfsCID;
        emit LogCIDChanged(feed, ipfsCID);
    }

    /// @inheritdoc IFeedRegistry
    function isFeed(address feed) external view override returns (bool) {
        return _feedConfigs[feed].minSignaturesThreshold > 0;
    }

    /// @inheritdoc IFeedRegistry
    function getFeedConfig(address feed) external view override returns (FeedConfig memory) {
        return _feedConfigs[feed];
    }

    /// @inheritdoc IFeedRegistry
    function getFeedPrice(address feed) external view override returns (uint256) {
        return _feedConfigs[feed].pricePerSecondScaled;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IFeedRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    function _validateFeed(address feed) internal view {
        if (_feedConfigs[feed].minSignaturesThreshold == 0) {
            revert NotFeed(feed);
        }
    }

    function _validateFeedConfig(
        FeedType feedType, 
        uint256 frequency, 
        uint256 minSignaturesThreshold, 
        string memory ipfsCID
    ) internal pure {
        if (minSignaturesThreshold == 0) {
            revert InvalidFeedConfig();
        }
        if (frequency == 0) {
            revert InvalidFeedConfig();
        }
        if (feedType != FeedType.PUBLIC && feedType != FeedType.PERSONAL) {
            revert InvalidFeedConfig();
        }
        if (keccak256(bytes(ipfsCID)) == keccak256(bytes(""))) {
            revert InvalidFeedConfig();
        }
    }
}
