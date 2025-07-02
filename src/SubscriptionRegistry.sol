// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {ERC165Checker} from "./libs/ERC165Checker.sol";
import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {IFeedRegistry} from "./interfaces/IFeedRegistry.sol";
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
    mapping(address => mapping(address => Subscription)) internal _subscriptions; // consumer => feed => dueTime

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

        Subscription memory subscription = _subscriptions[consumer][feed];

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

        _subscriptions[consumer][feed] = Subscription(uint64(dueTime), uint128(price), msg.sender);
        emit LogSubscribed(consumer, feed, dueTime);
    }

    /// @inheritdoc ISubscriptionRegistry
    function unsubscribe(address feed, address consumer) external override nonReentrant {
        Subscription memory subscription = _subscriptions[consumer][feed];
        require(subscription.owner == msg.sender, NotSubscriptionOwner(consumer));

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

    /// @inheritdoc ISubscriptionRegistry
    function isSubscribed(address consumer, address feed) external view returns (bool) {
        return _subscriptions[consumer][feed].dueTime > block.timestamp;
    }

    /// @inheritdoc ISubscriptionRegistry
    function getSubscriptionDueTime(address consumer, address feed) external view override returns (uint256) {
        return _subscriptions[consumer][feed].dueTime;
    }

    /// @inheritdoc ISubscriptionRegistry
    function getSubscriptionPrice(address feed) external view override returns (uint256) {
        return _prices[feed];
    }

    // /// @inheritdoc ISubscriptionRegistry
    // function getTreasury() external view override returns (ITreasury) {
    //     return _treasury;
    // }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(ISubscriptionRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    // function _validateSubscriptionFee(uint256 fee) internal pure {
    //     if (fee < MIN_SUBSCRIPTION_FEE || fee > MAX_SUBSCRIPTION_FEE) {
    //         revert WrongSubscriptionFee(fee);
    //     }
    // }
}
