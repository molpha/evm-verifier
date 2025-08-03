// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

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
            NotFeedOwner(msg.sender, feed)
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
        require(consumers.length > 0, EmptyConsumers());
        require(
            dueTime >= block.timestamp + MIN_SUBSCRIPTION_TIME,
            WrongSubscriptionTime(dueTime)
        );

        uint256 pricePerSecond = _consumerPricePerSecondScaled[feed];
        require(pricePerSecond > 0, CannotSubscribe());

        uint256 price = _pricingHelper.getPriceForTimespan(
            pricePerSecond,
            dueTime - block.timestamp
        );

        for (uint256 i = 0; i < consumers.length; i++) {
            _subscribe(consumers[i], feed, msg.sender, dueTime);
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
        require(feed != address(0), ZeroAddress());
        require(owner != address(0), ZeroAddress());
        require(
            dueTime >= block.timestamp + MIN_SUBSCRIPTION_TIME,
            WrongSubscriptionTime(dueTime)
        );
        require(IFeed(feed).getOwner() == owner, NotFeedOwner(owner, feed));
        require(
            _subscriptions[owner][feed].dueTime == 0,
            SubscriptionAlreadyExists(owner, feed)
        );

        uint256 pricePerSecondScaled = _pricingHelper.calculatePrice(feed);
        uint256 price = _pricingHelper.getPriceForTimespan(
            pricePerSecondScaled,
            dueTime - block.timestamp
        );

        _pricePerSecondScaled[feed] = pricePerSecondScaled;

        _subscribe(owner, feed, owner, dueTime);

        _treasury.deposit(owner, price);

        IFeed(feed).setConsumers(consumers, dueTime, new address[](0));
    }

    function extendSubscription(
        address feed,
        address consumer,
        uint256 dueTime
    ) external override nonReentrant {
        require(feed != address(0), ZeroAddress());
        require(
            dueTime >= block.timestamp + MIN_SUBSCRIPTION_TIME,
            WrongSubscriptionTime(dueTime)
        );

        uint256 currentDueTime = _subscriptions[msg.sender][feed].dueTime;
        uint256 timeSpan = currentDueTime > block.timestamp
            ? dueTime - currentDueTime
            : dueTime - block.timestamp;

        uint256 price;
        if (IFeed(feed).getOwner() == msg.sender) {
            price = _pricingHelper.getPriceForTimespan(
                _pricePerSecondScaled[feed],
                timeSpan
            );
        } else {
            require(
                _subscriptions[consumer][feed].owner == msg.sender,
                NotSubscriptionOwner(msg.sender)
            );
            price = _pricingHelper.getPriceForTimespan(
                _consumerPricePerSecondScaled[feed],
                timeSpan
            );
            _subscriptions[msg.sender][feed].dueTime = uint64(dueTime);
        }

        _treasury.deposit(msg.sender, price);

        emit LogSubscriptionUpdated(msg.sender, feed, dueTime);
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
            ZeroAddress()
        );
        // we can transfer only consumer's subscription
        require(
            consumer == msg.sender,
            CannotTransferSubscription()
        );

        Subscription memory subscription = _subscriptions[consumer][feed];

        // only active subscriptions can be transferred
        require(
            subscription.owner == msg.sender,
            NotSubscriptionOwner(msg.sender)
        );
        require(
            subscription.dueTime > block.timestamp,
            CannotTransferSubscription()
        );
        require(
            _subscriptions[newConsumer][feed].dueTime < block.timestamp,
            SubscriptionAlreadyExists(newConsumer, feed)
        );

        _subscriptions[newConsumer][feed] = Subscription(
            uint64(subscription.dueTime),
            msg.sender
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
    function recalculateSubscription(address feed) external override onlyFeedRegistry {
        address owner = IFeed(feed).getOwner();
        uint256 oldPricePerSecondScaled = _pricePerSecondScaled[feed];
        uint256 newPricePerSecondScaled = _pricingHelper.calculatePrice(feed);

        uint256 newDueTime = block.timestamp +
            (((_subscriptions[owner][feed].dueTime - block.timestamp) *
                oldPricePerSecondScaled) / newPricePerSecondScaled);

        _subscriptions[owner][feed].dueTime = uint64(newDueTime);

        emit LogSubscriptionUpdated(feed, owner, newDueTime);
    }

    /// @inheritdoc ISubscriptionRegistry
    function setTreasury(address treasury) external override onlyProtocolAdmin {
        address(treasury).shouldSupport(type(ITreasury).interfaceId);
        _treasury = ITreasury(treasury);
    }

    /// @inheritdoc ISubscriptionRegistry
    function getSubscription(
        address consumer,
        address feed
    ) external view override returns (Subscription memory subscription) {
        subscription = _subscriptions[consumer][feed];
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(ISubscriptionRegistry).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function _subscribe(
        address consumer,
        address feed,
        address owner,
        uint256 dueTime
    ) internal {
        require(consumer != address(0), ZeroAddress());

        require(
            _subscriptions[consumer][feed].dueTime < block.timestamp,
            SubscriptionAlreadyExists(consumer, feed)
        );

        _subscriptions[consumer][feed] = Subscription(uint64(dueTime), owner);
        emit LogSubscribed(consumer, feed, owner, dueTime);
    }
}
