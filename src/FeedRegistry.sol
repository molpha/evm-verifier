// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

import {ERC165Checker} from "./libs/ERC165Checker.sol";
import {PublicFeed} from "./PublicFeed.sol";
import {PersonalFeed} from "./PersonalFeed.sol";
import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {IFeed} from "./interfaces/IFeed.sol";
import {IFeedRegistry} from "./interfaces/IFeedRegistry.sol";
import {ISubscriptionRegistry} from "./interfaces/ISubscriptionRegistry.sol";
import {PricingHelper} from "./libs/PricingHelper.sol";

contract FeedRegistry is IFeedRegistry, ERC165, Initializable {
    using ERC165Checker for address;

    IAccessControlManager internal _accessControlManager;
    ISubscriptionRegistry internal _subscriptionRegistry;

    mapping(address => bool) internal _isFeed;

    modifier onlyProtocolAdmin() {
        _accessControlManager.verifyProtocolAdmin(msg.sender);
        _;
    }

    function initialize(address accessControlManager, address subscriptionRegistry) external override initializer {
        accessControlManager.shouldSupport(type(IAccessControlManager).interfaceId);
        subscriptionRegistry.shouldSupport(type(ISubscriptionRegistry).interfaceId);

        _accessControlManager = IAccessControlManager(accessControlManager);
        _subscriptionRegistry = ISubscriptionRegistry(subscriptionRegistry);
    }

    function createFeed(CreateFeedParams calldata params) external override {
        require(params.minSignaturesThreshold > 0, InvalidFeedConfig());
        require(params.frequency > 0, InvalidFeedConfig());
        require(keccak256(bytes(params.ipfsCID)) != keccak256(bytes("")), InvalidFeedConfig());
        require(params.subscriptionDueTime > block.timestamp, InvalidFeedConfig());
 
        address feed;
        if (params.feedType == IFeed.FeedType.PUBLIC) {
            feed = address(new PublicFeed(
                address(_accessControlManager),
                address(_subscriptionRegistry),
                msg.sender,
                params.frequency,
                params.minSignaturesThreshold,
                params.ipfsCID
            ));
        } else {
            feed = address(new PersonalFeed(
                address(_accessControlManager),
                address(_subscriptionRegistry),
                msg.sender,
                params.frequency,
                params.minSignaturesThreshold,
                params.ipfsCID
            ));
        }

        _isFeed[feed] = true;
        _subscriptionRegistry.subscribe(feed, msg.sender, params.subscriptionDueTime, params.defaultConsumers);

        emit LogFeedCreated(
            feed, 
            params.feedType, 
            params.frequency, 
            params.minSignaturesThreshold, 
            IFeed(feed).getPricePerSecondScaled(),
            params.ipfsCID
        );
    }

    function setAccessControlManager(address accessControlManager) external override onlyProtocolAdmin {
        address(accessControlManager).shouldSupport(type(IAccessControlManager).interfaceId);
        _accessControlManager = IAccessControlManager(accessControlManager);
    }

    function setSubscriptionRegistry(address subscriptionRegistry) external override onlyProtocolAdmin {
        address(subscriptionRegistry).shouldSupport(type(ISubscriptionRegistry).interfaceId);
        _subscriptionRegistry = ISubscriptionRegistry(subscriptionRegistry);
    }

    function isFeed(address feed) external view override returns (bool) {
        return _isFeed[feed];
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IFeedRegistry).interfaceId || super.supportsInterface(interfaceId);
    }
}
