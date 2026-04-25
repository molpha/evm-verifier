// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.31;

import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

import {ERC165Checker} from "./libs/ERC165Checker.sol";
import {IFeed} from "./interfaces/IFeed.sol";
import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {ISubscriptionRegistry} from "./interfaces/ISubscriptionRegistry.sol";
import {IPricingHelper} from "./interfaces/IPricingHelper.sol";
import {ITreasury} from "./interfaces/ITreasury.sol";

contract SubscriptionRegistry is
    ISubscriptionRegistry,
    ERC165,
    ReentrancyGuard,
    Initializable
{
    using ERC165Checker for address;

    // TODO: reconsider min and max values
    uint256 internal constant MIN_SUBSCRIPTION_TIME = 30 days;

    IAccessControlManager internal _accessControlManager;
    ITreasury internal _treasury;
    IPricingHelper internal _pricingHelper;

    mapping(address => mapping(address => Subscription))
        internal _subscriptions; // consumer => feed => subscription

    mapping(address => uint256) internal _pricePerSecondScaled; // feed => price per second scaled
    mapping(address => uint256) internal _consumerPricePerSecondScaled; // feed => consumer price per second scaled

    modifier onlyProtocolAdmin() {
        _accessControlManager.verifyProtocolAdmin(msg.sender);
        _;
    }

    modifier onlyFeedRegistry() {
        _accessControlManager.verifyFeedRegistry(msg.sender);
        _;
    }

    modifier onlyFeedRegistryOrOwner(address feed) {
        require(
            _accessControlManager.hasRole(
                _accessControlManager.FEED_REGISTRY(),
                msg.sender
            ) || IFeed(feed).getOwner() == msg.sender,
            "Not feed owner"
        );
        _;
    }

    function initialize(
        address accessControlManager,
        address treasury,
        address pricingHelper
    ) external override initializer {
        accessControlManager.shouldSupport(
            type(IAccessControlManager).interfaceId
        );
        treasury.shouldSupport(type(ITreasury).interfaceId);
        pricingHelper.shouldSupport(type(IPricingHelper).interfaceId);

        _accessControlManager = IAccessControlManager(accessControlManager);
        _treasury = ITreasury(treasury);
        _pricingHelper = IPricingHelper(pricingHelper);
    }

    /// @inheritdoc ISubscriptionRegistry
    function subscribe(
        address feed,
        uint256 dueTime,
        address[] calldata consumers
    ) external override nonReentrant {
        require(consumers.length > 0, "Empty consumers");
        require(
            dueTime >= block.timestamp + MIN_SUBSCRIPTION_TIME,
            "Wrong sub time"
        );

        uint256 pricePerSecond = _consumerPricePerSecondScaled[feed];
        require(pricePerSecond > 0, "Cannot subscribe");

        uint256 price = _pricingHelper.getPriceForTimespan(
            pricePerSecond,
            dueTime - block.timestamp
        );

        for (uint256 i = 0; i < consumers.length; i++) {
            _subscribe(SubscriptionType.Consumer, consumers[i], feed, msg.sender, dueTime, pricePerSecond);
        }

        _treasury.deposit(msg.sender, price * consumers.length);

        IFeed(feed).setConsumers(consumers, dueTime, new address[](0));
    }

    function initFeedSubscription(
        address feed,
        address owner,
        uint256 dueTime,
        address[] calldata consumers
    ) external override nonReentrant onlyFeedRegistry {
        require(feed != address(0), "Zero address");
        require(owner != address(0), "Zero address");
        require(
            dueTime >= block.timestamp + MIN_SUBSCRIPTION_TIME,
            "Wrong sub time"
        );
        require(IFeed(feed).getOwner() == owner, "Not feed owner");
        require(
            _subscriptions[owner][feed].dueTime == 0,
            "Sub exists"
        );

        uint256 pricePerSecondScaled = _pricingHelper.calculatePrice(feed);
        uint256 price = _pricingHelper.getPriceForTimespan(
            pricePerSecondScaled,
            dueTime - block.timestamp
        );

        _pricePerSecondScaled[feed] = pricePerSecondScaled;

        _subscribe(SubscriptionType.Owner, owner, feed, owner, dueTime, pricePerSecondScaled);

        _treasury.deposit(owner, price);

        IFeed(feed).setConsumers(consumers, dueTime, new address[](0));
    }

    function extendSubscription(
        address feed,
        address subscriber,
        uint256 dueTime
    ) external override nonReentrant {
        require(feed != address(0), "Zero address");
        require(
            dueTime >= block.timestamp + MIN_SUBSCRIPTION_TIME,
            "Wrong sub time"
        );

        uint256 currentDueTime = _subscriptions[subscriber][feed].dueTime;
        uint256 timeSpan = currentDueTime > block.timestamp
            ? dueTime - currentDueTime
            : dueTime - block.timestamp;

        uint256 pricePerSecondScaled;
        if (IFeed(feed).getOwner() == msg.sender) {
            pricePerSecondScaled = _pricePerSecondScaled[feed];
        } else {
            require(
                _subscriptions[subscriber][feed].owner == msg.sender,
                "Not sub owner"
            );
            pricePerSecondScaled = _consumerPricePerSecondScaled[feed];
        }
        uint256 price = _pricingHelper.getPriceForTimespan(
            pricePerSecondScaled,
            timeSpan
        );

        _subscriptions[subscriber][feed].dueTime = uint64(dueTime);

        _treasury.deposit(msg.sender, price);

        emit LogSubscriptionExtended(subscriber, feed, dueTime);
    }

    function transferSubscription(
        address consumer,
        address feed,
        address newConsumer
    ) external override nonReentrant {
        require(
            newConsumer != address(0) &&
                feed != address(0) &&
                consumer != address(0),
            "Zero address"
        );

        Subscription memory subscription = _subscriptions[consumer][feed];

        // only active subscriptions can be transferred
        require(
            subscription.owner == msg.sender,
            "Not sub owner"
        );
        require(
            subscription.dueTime > block.timestamp &&
                subscription.subscriptionType == SubscriptionType.Consumer,
            "Cannot transfer subscription"
        );
        require(
            _subscriptions[newConsumer][feed].dueTime < block.timestamp,
            "Sub exists"
        );

        _subscriptions[newConsumer][feed] = Subscription(
            msg.sender,
            uint64(subscription.dueTime),
            SubscriptionType.Consumer
        );

        delete _subscriptions[consumer][feed];
        _subscriptions[newConsumer][feed].dueTime = subscription.dueTime;

        IFeed(feed).removeConsumer(consumer);
        IFeed(feed).addConsumer(newConsumer, subscription.dueTime);

        emit LogSubscriptionTransferred(
            consumer,
            feed,
            newConsumer,
            subscription.dueTime
        );
    }

    function setConsumerPricePerSecondScaled(
        address feed,
        uint256 consumerPricePerSecondScaled
    ) external override onlyFeedRegistryOrOwner(feed) {
        _consumerPricePerSecondScaled[feed] = consumerPricePerSecondScaled;
    }

    /// @inheritdoc ISubscriptionRegistry
    function recalculateSubscription(
        address feed
    ) external override onlyFeedRegistry {
        address owner = IFeed(feed).getOwner();
        uint256 oldPricePerSecondScaled = _pricePerSecondScaled[feed];
        uint256 newPricePerSecondScaled = _pricingHelper.calculatePrice(feed);

        uint256 newDueTime = block.timestamp +
            (((_subscriptions[owner][feed].dueTime - block.timestamp) *
                oldPricePerSecondScaled) / newPricePerSecondScaled);

        _subscriptions[owner][feed].dueTime = uint64(newDueTime);
        _pricePerSecondScaled[feed] = newPricePerSecondScaled;

        emit LogSubscriptionUpdated(
            feed,
            owner,
            newDueTime,
            newPricePerSecondScaled
        );
    }

    /// @inheritdoc ISubscriptionRegistry
    function setTreasury(address treasury) external override onlyProtocolAdmin {
        address(treasury).shouldSupport(type(ITreasury).interfaceId);
        _treasury = ITreasury(treasury);
    }

    /// @inheritdoc ISubscriptionRegistry
    function getSubscription(
        address subscriber,
        address feed
    ) external view override returns (Subscription memory subscription) {
        subscription = _subscriptions[subscriber][feed];
    }

    function getPricePerSecondScaled(address feed) external view override returns (uint256) {
        return _pricePerSecondScaled[feed];
    }

    function getConsumerPricePerSecondScaled(address feed) external view override returns (uint256) {
        return _consumerPricePerSecondScaled[feed];
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(ISubscriptionRegistry).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function _subscribe(
        SubscriptionType subscriptionType,
        address subscriber,
        address feed,
        address subscriptionOwner,
        uint256 dueTime,
        uint256 pricePerSecondScaled
    ) internal {
        require(subscriber != address(0), "Zero address");

        require(
            _subscriptions[subscriber][feed].dueTime < block.timestamp,
            "Sub exists"
        );

        _subscriptions[subscriber][feed] = Subscription(
            subscriptionOwner,
            uint64(dueTime),
            subscriptionType
        );
        emit LogSubscribed(
            subscriber,
            feed,
            subscriptionOwner,
            dueTime,
            pricePerSecondScaled
        );
    }
}
