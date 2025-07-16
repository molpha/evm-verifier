// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

import {ERC165Checker} from "./libs/ERC165Checker.sol";
import {IFeed} from "./interfaces/IFeed.sol";
import {IFeedRegistry} from "./interfaces/IFeedRegistry.sol";
import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {ISubscriptionRegistry} from "./interfaces/ISubscriptionRegistry.sol";
import {PricingHelper} from "./libs/PricingHelper.sol";
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
    uint64 internal constant SUBSCRIPTION_TRANSFER_TIME_LOSS = 1 days;

    IAccessControlManager internal _accessControlManager;
    IFeedRegistry internal _feedRegistry;
    ITreasury internal _treasury;

    mapping(address => mapping(address => Subscription))
        internal _subscriptions; // consumer => feed => subscription

    modifier onlyProtocolAdmin() {
        _accessControlManager.verifyProtocolAdmin(msg.sender);
        _;
    }

    function initialize(address accessControlManager, address feedRegistry, address treasury) external override initializer {
        accessControlManager.shouldSupport(type(IAccessControlManager).interfaceId);
        feedRegistry.shouldSupport(type(IFeedRegistry).interfaceId);
        treasury.shouldSupport(type(ITreasury).interfaceId);

        _accessControlManager = IAccessControlManager(accessControlManager);
        _feedRegistry = IFeedRegistry(feedRegistry);
        _treasury = ITreasury(treasury);
    }

    /// @inheritdoc ISubscriptionRegistry
    function subscribe(
        address feed,
        address owner,
        uint256 dueTime,
        address[] calldata consumers
    ) external override nonReentrant {
        require(owner != address(0), ZeroAddress());
        require(_feedRegistry.isFeed(feed), NotFeed(feed));
        require(
            dueTime >= block.timestamp + MIN_SUBSCRIPTION_TIME,
            WrongSubscriptionTime(dueTime)
        );

        IFeed.FeedType feedType = IFeed(feed).getFeedType();

        if (feedType == IFeed.FeedType.PERSONAL) {
            _createPersonalSubscription(consumers, feed, owner, dueTime);
        } else if (feedType == IFeed.FeedType.PUBLIC) {
            _createPublicSubscription(consumers, feed, owner, dueTime);
        } else {
            revert CannotSubscribe();
        }
    }

    function extendSubscription(
        address consumer,
        address feed,
        uint256 dueTime
    ) external override nonReentrant {
        require(
            dueTime >= block.timestamp + MIN_SUBSCRIPTION_TIME,
            WrongSubscriptionTime(dueTime)
        );
        require(consumer != address(0) && feed != address(0), ZeroAddress());
        require(
            _subscriptions[consumer][feed].owner == msg.sender,
            NotSubscriptionOwner(consumer)
        );

        if (IFeed(feed).getFeedType() == IFeed.FeedType.PERSONAL) {
            require(consumer == IFeed(feed).getOwner(), CannotExtendSubscription());
        }

        uint256 price = PricingHelper.getPriceForTimespan(
            IFeed(feed).getPricePerSecondScaled(),
            dueTime - block.timestamp
        );

        _treasury.deposit(msg.sender, price);

        _subscriptions[consumer][feed].dueTime = uint64(dueTime);
        emit LogSubscriptionExtended(consumer, feed, dueTime);
    }

    /// @inheritdoc ISubscriptionRegistry
    function unsubscribe(address feed, address consumer) external override nonReentrant {
        require(
            _subscriptions[consumer][feed].owner == msg.sender,
            NotSubscriptionOwner(msg.sender)
        );

        // we don't need to delete the subscription, because it will be expired
        _subscriptions[consumer][feed].dueTime = uint64(block.timestamp);
        emit LogUnsubscribed(consumer, feed);
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

        // only public feed subscriptions can be transferred
        require(IFeed(feed).getFeedType() == IFeed.FeedType.PUBLIC, CannotTransferSubscription());

        Subscription memory subscription = _subscriptions[consumer][feed];

        require(subscription.owner == msg.sender, NotSubscriptionOwner(msg.sender));
        require(
            subscription.dueTime >
                block.timestamp + SUBSCRIPTION_TRANSFER_TIME_LOSS,
            CannotTransferSubscription()
        );

        uint64 newDueTime = subscription.dueTime - SUBSCRIPTION_TRANSFER_TIME_LOSS;
        subscription.dueTime = newDueTime;

        _subscriptions[newConsumer][feed] = subscription;
        // set old consumer subscription to expired
        _subscriptions[consumer][feed].dueTime = uint64(block.timestamp);

        emit LogSubscriptionTransferred(consumer, feed, newConsumer, newDueTime);
    }

    /// @inheritdoc ISubscriptionRegistry
    function setFeedRegistry(address feedRegistry) external override onlyProtocolAdmin {
        address(feedRegistry).shouldSupport(type(IFeedRegistry).interfaceId);
        _feedRegistry = IFeedRegistry(feedRegistry);
    }

    /// @inheritdoc ISubscriptionRegistry
    function setTreasury(address treasury) external override onlyProtocolAdmin {
        address(treasury).shouldSupport(type(ITreasury).interfaceId);
        _treasury = ITreasury(treasury);
    }

    /// @inheritdoc ISubscriptionRegistry
    function isSubscribed(
        address consumer,
        address feed
    ) external view override returns (bool isConsumerSubscribed) {
        IFeed.FeedType feedType = IFeed(feed).getFeedType();
        Subscription storage subscription = _subscriptions[consumer][feed];

        if (feedType == IFeed.FeedType.PERSONAL) {
            isConsumerSubscribed =
                _subscriptions[subscription.owner][feed].dueTime >
                block.timestamp &&
                subscription.dueTime > block.timestamp;
        }

        isConsumerSubscribed = subscription.dueTime > block.timestamp;
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

    function _createPublicSubscription(
        address[] calldata consumers,
        address feed,
        address owner,
        uint256 dueTime
    ) internal {
        require(consumers.length > 0, EmptyConsumers());

        uint256 price = PricingHelper.getPriceForTimespan(
            IFeed(feed).getPricePerSecondScaled(),
            dueTime - block.timestamp
        );
        uint256 totalPrice = price * consumers.length;

        _treasury.deposit(owner, totalPrice);

        for (uint256 i = 0; i < consumers.length; i++) {
            _subscribe(consumers[i], feed, owner, dueTime);
        }
    }

    function _createPersonalSubscription(
        address[] calldata consumers,
        address feed,
        address owner,
        uint256 dueTime
    ) internal {
        require(owner == IFeed(feed).getOwner(), NotFeedOwner(owner, feed));

        if (_subscriptions[owner][feed].dueTime == 0) {
            // new subscription for new personal feed
            uint256 price = PricingHelper.getPriceForTimespan(
                IFeed(feed).getPricePerSecondScaled(),
                dueTime - block.timestamp
            );
            _treasury.deposit(owner, price);

            _subscribe(owner, feed, owner, dueTime);

            if (consumers.length > 0) {
                for (uint256 i = 0; i < consumers.length; i++) {
                    // child subscriptions are not expired, we check parent subscription due time instead
                    _subscribe(consumers[i], feed, owner, type(uint64).max);
                }
            }
        } else {
            // add consumers to existing personal feed
            require(msg.sender == owner, NotSubscriptionOwner(owner));
            require(consumers.length > 0, EmptyConsumers());
            
            for (uint256 i = 0; i < consumers.length; i++) {
                // child subscriptions are not expired, we check parent subscription due time instead
                _subscribe(consumers[i], feed, owner, type(uint64).max);
            }
        }
    }

    function _subscribe(
        address consumer,
        address feed,
        address owner,
        uint256 dueTime
    ) internal {
        require(
            consumer != address(0) && feed != address(0) && owner != address(0),
            ZeroAddress()
        );

        require(
            _subscriptions[consumer][feed].dueTime == 0,
            SubscriptionAlreadyExists(consumer, feed)
        );

        _subscriptions[consumer][feed] = Subscription(uint64(dueTime), owner);
        emit LogSubscribed(consumer, feed, owner, dueTime);
    }
}
