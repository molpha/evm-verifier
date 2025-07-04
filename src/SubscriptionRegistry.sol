// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {ERC165Checker} from "./libs/ERC165Checker.sol";
import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {IFeedRegistry} from "./interfaces/IFeedRegistry.sol";
import {IFeedRegistryStructs} from "./interfaces/IFeedRegistryStructs.sol";
import {ISubscriptionRegistry} from "./interfaces/ISubscriptionRegistry.sol";
import {PricingHelper} from "./libs/PricingHelper.sol";

contract SubscriptionRegistry is ISubscriptionRegistry, ERC165, ReentrancyGuard {
    using ERC165Checker for address;
    using SafeERC20 for IERC20;

    // TODO: reconsider min and max values
    uint256 internal constant MIN_SUBSCRIPTION_TIME = 1 days;
    uint256 internal constant MAX_SUBSCRIPTION_TIME = 1095 days; // 3 years 

    uint256 internal constant MAX_BPS = 10000; // 100%
    uint256 internal constant REFUND_FEE = 2000; // 20% refund fee

    uint256 internal constant BASE_PRICE = 1e5; // 0.1 USDC // ??????

    IAccessControlManager internal immutable _accessControlManager;
    IERC20 internal immutable _underlying;

    IFeedRegistry internal _feedRegistry;

    mapping(address => uint128) internal _prices; // feed => price per second
    mapping(address => mapping(address => Subscription)) internal _subscriptions; // consumer => feed => subscription
    mapping(address => PersonalFeedSubscription) internal _personalFeedSubscriptions; // feed => personal feed subscription

    modifier onlyProtocolAdmin() {
        _accessControlManager.verifyProtocolAdmin(msg.sender);
        _;
    }

    modifier onlyFeedRegistry() {
        if (msg.sender != address(_feedRegistry)) {
            revert NotFeedRegistry(msg.sender);
        }
        _;
    }

    modifier onlyFeedOwner(address feed) {
        require(_feedRegistry.isFeed(feed), NotAggregator(feed));
        IFeedRegistry.FeedConfig memory config = _feedRegistry.getFeedConfig(feed);
        if (msg.sender != config.owner) {
            revert NotFeedOwner(msg.sender, feed);
        }
        _;
    }

    constructor(IAccessControlManager accessControlManager, IERC20 underlying) {
        address(accessControlManager).shouldSupport(type(IAccessControlManager).interfaceId);
        require(underlying.totalSupply() > 0, "wrong underlying");

        _accessControlManager = accessControlManager;
        _underlying = underlying;
    }

    function initialize(
        IFeedRegistry feedRegistry
    ) external {
        address(feedRegistry).shouldSupport(type(IFeedRegistry).interfaceId);

        _feedRegistry = feedRegistry;
    }

    /// @inheritdoc ISubscriptionRegistry
    function subscribe(address consumer, address feed, uint256 timespan) external override nonReentrant {
        require(timespan > MIN_SUBSCRIPTION_TIME && timespan <= MAX_SUBSCRIPTION_TIME, WrongSubscriptionTime(timespan));
        require(consumer != address(0) && feed != address(0), ZeroAddress());

        uint256 price = PricingHelper.getPriceForTimespan(_feedRegistry.getFeedPrice(feed), timespan);
        require(price > 0, NotAggregator(feed));

        IFeedRegistry.FeedConfig memory config = _feedRegistry.getFeedConfig(feed);
        
        // Handle personal feeds differently
        if (config.feedType == IFeedRegistryStructs.FeedType.PERSONAL) {
            _subscribeToPersonalFeed(consumer, feed, timespan, price, config.owner);
        } else {
            _subscribeToPublicFeed(consumer, feed, timespan, price);
        }
    }

    /// @inheritdoc ISubscriptionRegistry
    function batchSubscribe(address[] calldata consumers, address feed, uint256 timespan) external override nonReentrant {
        require(consumers.length > 0, EmptyBatchSubscribe());
        require(timespan > MIN_SUBSCRIPTION_TIME && timespan <= MAX_SUBSCRIPTION_TIME, WrongSubscriptionTime(timespan));
        require(feed != address(0), ZeroAddress());

        uint256 price = PricingHelper.getPriceForTimespan(_feedRegistry.getFeedPrice(feed), timespan);
        require(price > 0, NotAggregator(feed));

        IFeedRegistry.FeedConfig memory config = _feedRegistry.getFeedConfig(feed);
        
        // Calculate total amount needed
        uint256 totalAmount = price * timespan * consumers.length;
        
        // Handle personal feeds differently
        if (config.feedType == IFeedRegistryStructs.FeedType.PERSONAL) {
            _batchSubscribeToPersonalFeed(consumers, feed, timespan, price, config.owner, totalAmount);
        } else {
            _batchSubscribeToPublicFeed(consumers, feed, timespan, price, totalAmount);
        }
    }

    /// @inheritdoc ISubscriptionRegistry
    function unsubscribe(address feed, address consumer) external override nonReentrant {
        IFeedRegistry.FeedConfig memory config = _feedRegistry.getFeedConfig(feed);
        
        if (config.feedType == IFeedRegistryStructs.FeedType.PERSONAL) {
            _unsubscribeFromPersonalFeed(feed, consumer, config.owner);
        } else {
            _unsubscribeFromPublicFeed(feed, consumer);
        }
    }

    /// @inheritdoc ISubscriptionRegistry
    function isSubscribed(address consumer, address feed) external view returns (bool) {
        IFeedRegistry.FeedConfig memory config = _feedRegistry.getFeedConfig(feed);
        
        if (config.feedType == IFeedRegistryStructs.FeedType.PERSONAL) {
            // For personal feeds, check if main subscription is active and consumer has access
            PersonalFeedSubscription storage personalSub = _personalFeedSubscriptions[feed];
            return personalSub.mainSubscription.dueTime > block.timestamp && 
                   personalSub.consumerAccess[consumer];
        } else {
            // For public feeds, check the regular subscription
            return _subscriptions[consumer][feed].dueTime > block.timestamp;
        }
    }

    /// @inheritdoc ISubscriptionRegistry
    function getSubscriptionDueTime(address consumer, address feed) external view override returns (uint256) {
        IFeedRegistry.FeedConfig memory config = _feedRegistry.getFeedConfig(feed);
        
        if (config.feedType == IFeedRegistryStructs.FeedType.PERSONAL) {
            // For personal feeds, return the main subscription due time if consumer has access
            PersonalFeedSubscription storage personalSub = _personalFeedSubscriptions[feed];
            if (personalSub.consumerAccess[consumer]) {
                return personalSub.mainSubscription.dueTime;
            }
            return 0;
        } else {
            return _subscriptions[consumer][feed].dueTime;
        }
    }

    /// @inheritdoc ISubscriptionRegistry
    function getSubscriptionPrice(address feed) external view override returns (uint256) {
        return _prices[feed];
    }

    /// @inheritdoc ISubscriptionRegistry
    function grantPersonalFeedAccess(address consumer, address feed) external override onlyFeedOwner(feed) {
        IFeedRegistry.FeedConfig memory config = _feedRegistry.getFeedConfig(feed);
        require(config.feedType == IFeedRegistryStructs.FeedType.PERSONAL, NotAggregator(feed));
        
        PersonalFeedSubscription storage personalSub = _personalFeedSubscriptions[feed];
        require(personalSub.mainSubscription.dueTime > block.timestamp, PersonalFeedMainSubscriptionExpired(feed));
        
        personalSub.consumerAccess[consumer] = true;
        emit LogPersonalFeedAccessGranted(consumer, feed, msg.sender);
    }

    /// @inheritdoc ISubscriptionRegistry
    function revokePersonalFeedAccess(address consumer, address feed) external override onlyFeedOwner(feed) {
        IFeedRegistry.FeedConfig memory config = _feedRegistry.getFeedConfig(feed);
        require(config.feedType == IFeedRegistryStructs.FeedType.PERSONAL, NotAggregator(feed));
        
        PersonalFeedSubscription storage personalSub = _personalFeedSubscriptions[feed];
        personalSub.consumerAccess[consumer] = false;
        emit LogPersonalFeedAccessRevoked(consumer, feed, msg.sender);
    }

    /// @inheritdoc ISubscriptionRegistry
    function hasPersonalFeedAccess(address consumer, address feed) external view override returns (bool hasAccess) {
        IFeedRegistry.FeedConfig memory config = _feedRegistry.getFeedConfig(feed);
        
        if (config.feedType == IFeedRegistryStructs.FeedType.PERSONAL) {
            PersonalFeedSubscription storage personalSub = _personalFeedSubscriptions[feed];
            return personalSub.consumerAccess[consumer] && personalSub.mainSubscription.dueTime > block.timestamp;
        }
        
        return false;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(ISubscriptionRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    // Internal functions
    function _subscribeToPublicFeed(address consumer, address feed, uint256 timespan, uint256 priceTotal) internal {
        Subscription memory subscription = _subscriptions[consumer][feed];
        
        // Get the price per second from the feed registry for comparison
        uint256 pricePerSecond = _feedRegistry.getFeedPrice(feed);

        // we cannot extend subscription if subscription price changed
        // in this case we can extend only if due time is less than minimum subscription time
        // this added to avoid complex refund logic, where we need to refund with different prices 
        if (subscription.price != pricePerSecond && subscription.dueTime > block.timestamp + MIN_SUBSCRIPTION_TIME) {
            revert CannotExtendSubscription();
        }

        uint256 amount = priceTotal;
        // _underlying.safeTransferFrom(msg.sender, address(_treasury), amount);
        // _treasury.collectFee(amount * _subscriptionFee / WAD);

        uint256 dueTime = subscription.dueTime > block.timestamp ? subscription.dueTime + timespan : block.timestamp + timespan;

        _subscriptions[consumer][feed] = Subscription(uint64(dueTime), uint128(pricePerSecond), msg.sender);
        emit LogSubscribed(consumer, feed, dueTime);
    }

    function _subscribeToPersonalFeed(address consumer, address feed, uint256 timespan, uint256 priceTotal, address feedOwner) internal {
        // Only feed owner can subscribe to personal feeds
        require(msg.sender == feedOwner, NotFeedOwner(msg.sender, feed));
        
        PersonalFeedSubscription storage personalSub = _personalFeedSubscriptions[feed];
        Subscription memory mainSubscription = personalSub.mainSubscription;
        
        // Get the price per second from the feed registry for comparison
        uint256 pricePerSecond = _feedRegistry.getFeedPrice(feed);

        // we cannot extend subscription if subscription price changed
        if (mainSubscription.price != pricePerSecond && mainSubscription.dueTime > block.timestamp + MIN_SUBSCRIPTION_TIME) {
            revert CannotExtendSubscription();
        }

        uint256 amount = priceTotal;
        // _underlying.safeTransferFrom(msg.sender, address(_treasury), amount);

        uint256 dueTime = mainSubscription.dueTime > block.timestamp ? mainSubscription.dueTime + timespan : block.timestamp + timespan;

        personalSub.mainSubscription = Subscription(uint64(dueTime), uint128(pricePerSecond), feedOwner);
        personalSub.consumerAccess[consumer] = true;
        
        emit LogSubscribed(consumer, feed, dueTime);
    }

    function _batchSubscribeToPublicFeed(address[] calldata consumers, address feed, uint256 timespan, uint256 priceTotal, uint256 totalAmount) internal {
        // _underlying.safeTransferFrom(msg.sender, address(_treasury), totalAmount);
        
        // Get the price per second from the feed registry for comparison
        uint256 pricePerSecond = _feedRegistry.getFeedPrice(feed);

        uint256 dueTime = block.timestamp + timespan;

        for (uint256 i = 0; i < consumers.length; i++) {
            address consumer = consumers[i];
            require(consumer != address(0), ZeroAddress());
            
            Subscription memory subscription = _subscriptions[consumer][feed];
            
            if (subscription.price != pricePerSecond && subscription.dueTime > block.timestamp + MIN_SUBSCRIPTION_TIME) {
                revert CannotExtendSubscription();
            }

            uint256 consumerDueTime = subscription.dueTime > block.timestamp ? subscription.dueTime + timespan : dueTime;
            _subscriptions[consumer][feed] = Subscription(uint64(consumerDueTime), uint128(pricePerSecond), msg.sender);
        }

        emit LogBatchSubscribed(consumers, feed, dueTime);
    }

    function _batchSubscribeToPersonalFeed(address[] calldata consumers, address feed, uint256 timespan, uint256 priceTotal, address feedOwner, uint256 totalAmount) internal {
        // Only feed owner can batch subscribe to personal feeds
        require(msg.sender == feedOwner, NotFeedOwner(msg.sender, feed));
        
        PersonalFeedSubscription storage personalSub = _personalFeedSubscriptions[feed];
        Subscription memory mainSubscription = personalSub.mainSubscription;
        
        // Get the price per second from the feed registry for comparison
        uint256 pricePerSecond = _feedRegistry.getFeedPrice(feed);

        if (mainSubscription.price != pricePerSecond && mainSubscription.dueTime > block.timestamp + MIN_SUBSCRIPTION_TIME) {
            revert CannotExtendSubscription();
        }

        // _underlying.safeTransferFrom(msg.sender, address(_treasury), totalAmount);

        uint256 dueTime = mainSubscription.dueTime > block.timestamp ? mainSubscription.dueTime + timespan : block.timestamp + timespan;
        personalSub.mainSubscription = Subscription(uint64(dueTime), uint128(pricePerSecond), feedOwner);

        for (uint256 i = 0; i < consumers.length; i++) {
            address consumer = consumers[i];
            require(consumer != address(0), ZeroAddress());
            personalSub.consumerAccess[consumer] = true;
        }

        emit LogBatchSubscribed(consumers, feed, dueTime);
    }

    function _unsubscribeFromPublicFeed(address feed, address consumer) internal {
        Subscription memory subscription = _subscriptions[consumer][feed];
        require(subscription.owner == msg.sender, NotSubscriptionOwner(consumer));
        
        // Check if subscription exists (dueTime > 0)
        require(subscription.dueTime > 0, NotSubscriptionOwner(consumer));

        // For expired subscriptions, just delete them without refund
        if (subscription.dueTime <= block.timestamp) {
            delete _subscriptions[consumer][feed];
            emit LogUnsubscribed(consumer, feed);
            return;
        }

        // we don't want to refund less than min subscription time
        // it will prevent from spamming (subscribe => read => unsubscribe in one tx)
        uint256 minSubscriptionEnd = block.timestamp + MIN_SUBSCRIPTION_TIME;
        if (subscription.dueTime <= minSubscriptionEnd) {
            revert CannotUnsubscribe(subscription.dueTime);
        }

        uint256 unusedAmount = subscription.price * (subscription.dueTime - minSubscriptionEnd);
        uint256 refundAmount = unusedAmount * REFUND_FEE / MAX_BPS;

        delete _subscriptions[consumer][feed];

        // _treasury.makeRefund(consumer, refundAmount);

        emit LogUnsubscribed(consumer, feed);
    }

    function _unsubscribeFromPersonalFeed(address feed, address consumer, address feedOwner) internal {
        PersonalFeedSubscription storage personalSub = _personalFeedSubscriptions[feed];
        require(personalSub.mainSubscription.owner == msg.sender, NotSubscriptionOwner(consumer));

        // For personal feeds, we just revoke access rather than refunding
        // since the main subscription is maintained by the feed owner
        personalSub.consumerAccess[consumer] = false;

        emit LogUnsubscribed(consumer, feed);
    }
}
