// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";

import {ERC165Checker} from "./libs/ERC165Checker.sol";
import {PublicFeed} from "./PublicFeed.sol";
import {PersonalFeed} from "./PersonalFeed.sol";
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
    uint256 internal constant PERSONAL_FEED_PRICE_MULTIPLIER = 3;
    uint256 internal constant MIN_SUBSCRIPTION_TIME = 30 days;

    IAccessControlManager internal immutable _accessControlManager;
    INodeRegistry internal immutable _nodeRegistry;
    ISubscriptionRegistry internal immutable _subscriptionRegistry;

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

    // TODO: add fees collection
    // TDOD: price is missing on subgraph for new feeds
    /// @inheritdoc IFeedRegistry
    function createPublicFeed(
        uint256 frequency, 
        uint256 minSignaturesThreshold, 
        string memory ipfsCID,
        address defaultConsumer,
        uint256 subscriptionDueTime
    ) external override {
        _validateFeedConfig(frequency, minSignaturesThreshold, ipfsCID);

        address feed = address(new PublicFeed(
            _accessControlManager,
            _nodeRegistry,
            _subscriptionRegistry,
            msg.sender,
            minSignaturesThreshold,
            frequency,
            ipfsCID
        ));

        _subscriptionRegistry.subscribe(defaultConsumer, feed, msg.sender, subscriptionDueTime);
        emit LogFeedCreated(feed, IFeed.FeedType.PUBLIC, frequency, minSignaturesThreshold, ipfsCID);
    }

    // TDOD: price is missing on subgraph for new feeds
    function createPersonalFeed(
        uint256 frequency, 
        uint256 minSignaturesThreshold, 
        string memory ipfsCID,
        uint256 subscriptionDueTime
    ) external override {
        _validateFeedConfig(frequency, minSignaturesThreshold, ipfsCID);

        address feed = address(new PersonalFeed(
            _accessControlManager,
            _nodeRegistry,
            _subscriptionRegistry,
            msg.sender,
            minSignaturesThreshold,
            frequency,
            ipfsCID
        ));

        _subscriptionRegistry.subscribe(
            msg.sender,
            feed,
            msg.sender,
            subscriptionDueTime
        );
        emit LogFeedCreated(feed, IFeed.FeedType.PERSONAL, frequency, minSignaturesThreshold, ipfsCID);
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IFeedRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    function _validateFeedConfig(
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
        if (keccak256(bytes(ipfsCID)) == keccak256(bytes(""))) {
            revert InvalidFeedConfig();
        }
    }
}
