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
    uint256 internal constant PERSONAL_FEED_PRICE_MULTIPLIER = 3;

    IAccessControlManager internal immutable _accessControlManager;
    INodeRegistry internal immutable _nodeRegistry;
    ISubscriptionRegistry internal immutable _subscriptionRegistry;

    mapping(address => bool) internal _feedExists;

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
    /// @inheritdoc IFeedRegistry
    function createFeed(IFeed.FeedType feedType, uint256 frequency, uint256 minSignaturesThreshold, string memory ipfsCID) external override onlyFeedManager {
        _validateFeedConfig(feedType, frequency, minSignaturesThreshold, ipfsCID);

        address feed = address(new Feed(
            feedType,
            _accessControlManager,
            _nodeRegistry,
            _subscriptionRegistry,
            msg.sender,
            minSignaturesThreshold,
            frequency,
            ipfsCID
        ));

        emit LogFeedCreated(feed, feedType, frequency, minSignaturesThreshold, ipfsCID);
    }

    /// @inheritdoc IFeedRegistry
    function isFeed(address feed) external view override returns (bool feedExists) {
        feedExists = _feedExists[feed];
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IFeedRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    function _validateFeedConfig(
        IFeed.FeedType feedType, 
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
        if (feedType != IFeed.FeedType.PUBLIC && feedType != IFeed.FeedType.PERSONAL) {
            revert InvalidFeedConfig();
        }
        if (keccak256(bytes(ipfsCID)) == keccak256(bytes(""))) {
            revert InvalidFeedConfig();
        }
    }
}
