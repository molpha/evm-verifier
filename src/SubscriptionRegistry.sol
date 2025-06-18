// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {ERC165Checker} from "./libs/ERC165Checker.sol";
import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {IFeedsRegistry} from "./interfaces/IFeedsRegistry.sol";
import {ISubscriptionsRegistry} from "./interfaces/ISubscriptionsRegistry.sol";

contract SubscriptionsRegistry is ISubscriptionsRegistry, ERC165, ReentrancyGuard {
    using ERC165Checker for address;
    using SafeERC20 for IERC20;

    // TODO: reconsider min and max values
    uint256 internal constant MIN_SUBSCRIPTION_TIME = 1 days;
    uint256 internal constant MAX_SUBSCRIPTION_TIME = 365 days;

    uint256 internal constant MIN_SUBSCRIPTION_PRICE = 1e13; // 0.00001 FXD // per second -> 0.864 FXD per day -> 315.36 FXD per year
    uint256 internal constant MAX_SUBSCRIPTION_PRICE = 2e14; // 0.0002 FXD // per second -> 17.28 FXD per day -> 6307.2 FXD per year
    
    uint256 internal constant WAD = 1e18; // 100%
    uint256 internal constant MIN_SUBSCRIPTION_FEE = 1e14; // 0.01%
    uint256 internal constant MAX_SUBSCRIPTION_FEE = 1e17; // 10%

    IAccessControlManager internal immutable _accessControlManager;
    IERC20 internal immutable _underlying;

    IFeedsRegistry internal _feedsRegistry;
    // ITreasury internal _treasury;

    uint256 internal _subscriptionFee; // 100% = 1e18; 1% = 1e16; 0.1% = 1e15; 0.01% = 1e14; 0.001% = 1e13;

    mapping(address => uint128) internal _prices; // aggregator => price per second
    mapping(address => mapping(address => Subscription)) internal _subscriptions; // consumer => aggregator => dueTime

    modifier onlyProtocolAdmin() {
        _accessControlManager.verifyProtocolAdmin(msg.sender);
        _;
    }

    modifier onlyFeedsRegistry() {
        if (msg.sender != address(_feedsRegistry)) {
            revert NotFeedsRegistry(msg.sender);
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
        IFeedsRegistry feedsRegistry,
        // ITreasury treasury,
        uint256 subscriptionFee
    ) external {
        if (_subscriptionFee != 0) {
            revert("AlreadyInitialized()");
        }
        address(feedsRegistry).shouldSupport(type(IFeedsRegistry).interfaceId);
        // address(treasury).shouldSupport(type(ITreasury).interfaceId);
        _validateSubscriptionFee(subscriptionFee);

        _feedsRegistry = feedsRegistry;
        // _treasury = treasury;
        _subscriptionFee = subscriptionFee;
    }

    /// @inheritdoc ISubscriptionsRegistry
    function subscribe(address consumer, address aggregator, uint256 timespan) external override nonReentrant {
        if (timespan < MIN_SUBSCRIPTION_TIME || timespan > MAX_SUBSCRIPTION_TIME) {
            revert WrongSubscriptionTime(timespan);
        }

        uint256 price = _prices[aggregator];
        if (price == 0) {
            revert NotAggregator(aggregator);
        }

        Subscription memory subscription = _subscriptions[consumer][aggregator];

        // we cannot extend subscription if subscription price changed
        // in this case we can extend only if due time is less than minimum subscription time
        // this added to avoid complex refund logic, where we need to refund with different prices 
        if (subscription.price != price && subscription.dueTime > block.timestamp + MIN_SUBSCRIPTION_TIME) {
            revert CannotExtendSubscription();
        }

        uint256 amount = price * timespan;
        // _underlying.safeTransferFrom(msg.sender, address(_treasury), amount);
        // _treasury.collectFee(amount * _subscriptionFee / WAD);

        uint256 dueTime = subscription.dueTime > block.timestamp ? subscription.dueTime + timespan : block.timestamp + timespan;

        _subscriptions[consumer][aggregator] = Subscription(uint64(dueTime), uint128(price));
        emit LogSubscribed(consumer, aggregator, dueTime);
    }

    /// @inheritdoc ISubscriptionsRegistry
    function unsubscribe(address feed) external override nonReentrant {
        address consumer = msg.sender;
        Subscription memory subscription = _subscriptions[consumer][feed];
        // we don't want to refund less than min subscription time
        // it will prevent from spamming (subscribe => read => unsubscribe in one tx)
        uint256 minSubscriptionEnd = block.timestamp + MIN_SUBSCRIPTION_TIME;
        if (subscription.dueTime <= minSubscriptionEnd) {
            revert CannotUnsubscribe(subscription.dueTime);
        }

        uint256 unusedAmount = subscription.price * (subscription.dueTime - minSubscriptionEnd);
        // we won't refund subscription fee
        uint256 refundAmount = unusedAmount * (WAD - _subscriptionFee) / WAD;

        delete _subscriptions[consumer][feed];

        // _treasury.makeRefund(consumer, refundAmount);

        emit LogUnsubscribed(consumer, feed);
    }

    function setSubscriptionFee(uint256 fee) external override onlyProtocolAdmin {
        _validateSubscriptionFee(fee);
        _subscriptionFee = fee;
        emit LogSubscriptionFeeSet(fee);
    }

    /// @inheritdoc ISubscriptionsRegistry
    function setSubscriptionPrice(address aggregator, uint128 price) external override onlyFeedsRegistry {
        if (price < MIN_SUBSCRIPTION_PRICE || price > MAX_SUBSCRIPTION_PRICE) {
            revert WrongSubscriptionPrice(price);
        }
        if (!_feedsRegistry.isFeed(aggregator)) {
            revert NotAggregator(aggregator);
        }

        _prices[aggregator] = price;
        emit LogSubscriptionPriceSet(aggregator, price);
    }

    /// @inheritdoc ISubscriptionsRegistry
    function isSubscribed(address consumer, address aggregator) external view returns (bool) {
        return _subscriptions[consumer][aggregator].dueTime > block.timestamp;
    }

    /// @inheritdoc ISubscriptionsRegistry
    function getSubscriptionDueTime(address consumer, address aggregator) external view override returns (uint256) {
        return _subscriptions[consumer][aggregator].dueTime;
    }

    /// @inheritdoc ISubscriptionsRegistry
    function getSubscriptionPrice(address feed) external view override returns (uint256) {
        return _prices[feed];
    }

    /// @inheritdoc ISubscriptionsRegistry
    function getSubscriptionFee() external view override returns (uint256) {
        return _subscriptionFee;
    }

    // /// @inheritdoc ISubscriptionsRegistry
    // function getTreasury() external view override returns (ITreasury) {
    //     return _treasury;
    // }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(ISubscriptionsRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    function _validateSubscriptionFee(uint256 fee) internal pure {
        if (fee < MIN_SUBSCRIPTION_FEE || fee > MAX_SUBSCRIPTION_FEE) {
            revert WrongSubscriptionFee(fee);
        }
    }
}
