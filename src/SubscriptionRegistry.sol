// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {ERC165Checker} from "./libs/ERC165Checker.sol";
import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {IFeed} from "./interfaces/IFeed.sol";
import {IFeedRegistry} from "./interfaces/IFeedRegistry.sol";

import {ISubscriptionRegistry} from "./interfaces/ISubscriptionRegistry.sol";
import {PricingHelper} from "./libs/PricingHelper.sol";
import {ITreasury} from "./interfaces/ITreasury.sol";

// TODO: add payment logic
contract SubscriptionRegistry is
    ISubscriptionRegistry,
    ERC165,
    ReentrancyGuard
{
    using ERC165Checker for address;
    using SafeERC20 for IERC20;

    // TODO: reconsider min and max values
    uint256 internal constant MIN_SUBSCRIPTION_TIME = 1 days;
    uint256 internal constant MAX_SUBSCRIPTION_TIME = 1095 days; // 3 years

    uint256 internal constant MAX_BPS = 10000; // 100%
    uint256 internal constant REFUND_FEE = 2000; // 20% refund fee

    IAccessControlManager internal immutable _accessControlManager;
    IERC20 internal immutable _underlying;

    IFeedRegistry internal _feedRegistry;
    ITreasury internal _treasury;

    mapping(address => mapping(address => Subscription))
        internal _subscriptions; // consumer => feed => subscription
    mapping(address => mapping(address => address))
        internal _personalFeedAccess; // feed => consumer => owner

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
        address(accessControlManager).shouldSupport(
            type(IAccessControlManager).interfaceId
        );
        require(underlying.totalSupply() > 0, "wrong underlying");

        _accessControlManager = accessControlManager;
        _underlying = underlying;
    }

    function initialize(IFeedRegistry feedRegistry) external {
        address(feedRegistry).shouldSupport(type(IFeedRegistry).interfaceId);

        _feedRegistry = feedRegistry;
    }

    /// @inheritdoc ISubscriptionRegistry
    function subscribe(
        address[] calldata consumers,
        address feed,
        uint256 dueTime
    )
        external
        override
        nonReentrant
    {
        _checkSubscriptionData(consumers, feed, msg.sender, dueTime);
        _batchSubscribe(consumers, feed, msg.sender, dueTime);
    }

    function subscribe(
        address consumer,
        address feed,
        uint256 dueTime
    )
        external
        override
        nonReentrant
    {
        _checkSubscriptionData(consumer, feed, msg.sender, dueTime);
        _subscribe(consumer, feed, msg.sender, dueTime);
    }

    function subscribe(
        address[] calldata consumers,
        address feed,
        address owner,
        uint256 dueTime
    )
        external
        override
        nonReentrant
        onlyFeedRegistry
    {
        _checkSubscriptionData(consumers, feed, owner, dueTime);
        _batchSubscribe(consumers, feed, owner, dueTime);
    }

    function subscribe(
        address consumer,
        address feed,
        address owner,
        uint256 dueTime
    )
        external
        override
        nonReentrant
        onlyFeedRegistry
    {
        _checkSubscriptionData(consumer, feed, owner, dueTime);
        _subscribe(consumer, feed, owner, dueTime);
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

        _subscriptions[consumer][feed].dueTime = uint64(dueTime);
        emit LogSubscriptionExtended(consumer, feed, dueTime);
    }

    /// @inheritdoc ISubscriptionRegistry
    function grantAccess(
        address consumer,
        address feed
    ) external override nonReentrant {
        require(consumer != address(0) && feed != address(0), ZeroAddress());
        require(
            msg.sender == IFeed(feed).getOwner(),
            NotFeedOwner(msg.sender, feed)
        );

        _subscriptions[consumer][feed] = Subscription(
            type(uint64).max,
            msg.sender
        );

        emit LogAccessGranted(consumer, feed, msg.sender);
    }

    function grantAccess(
        address[] calldata consumers,
        address feed
    ) external override nonReentrant {
        require(consumers.length > 0, ZeroAddress());
        require(feed != address(0), ZeroAddress());
        require(
            msg.sender == IFeed(feed).getOwner(),
            NotFeedOwner(msg.sender, feed)
        );

        for (uint256 i = 0; i < consumers.length; i++) {
            _subscriptions[consumers[i]][feed] = Subscription(
                type(uint64).max,
                msg.sender
            );

            emit LogAccessGranted(consumers[i], feed, msg.sender);
        }
    }

    function revokeAccess(
        address consumer,
        address feed
    ) external override nonReentrant {
        require(
            _subscriptions[consumer][feed].owner == msg.sender,
            NotSubscriptionOwner(consumer)
        );
        delete _subscriptions[consumer][feed];
        emit LogAccessRevoked(consumer, feed, msg.sender);
    }

    function revokeAccess(
        address[] calldata consumers,
        address feed
    ) external override nonReentrant {
        for (uint256 i = 0; i < consumers.length; i++) {
            require(
                _subscriptions[consumers[i]][feed].owner == msg.sender,
                NotSubscriptionOwner(consumers[i])
            );
            delete _subscriptions[consumers[i]][feed];
            emit LogAccessRevoked(consumers[i], feed, msg.sender);
        }
    }

    /// @inheritdoc ISubscriptionRegistry
    function unsubscribe(
        address feed,
        address consumer
    ) external override nonReentrant {
        require(
            _subscriptions[consumer][feed].owner == msg.sender,
            NotSubscriptionOwner(consumer)
        );

        delete _subscriptions[consumer][feed];
        emit LogUnsubscribed(consumer, feed);
    }

    function transferSubscription(
        address consumer,
        address feed,
        address newConsumer
    ) external override nonReentrant {
        require(
            _subscriptions[consumer][feed].owner == msg.sender,
            NotSubscriptionOwner(consumer)
        );
        _subscriptions[newConsumer][feed] = _subscriptions[consumer][feed];
        delete _subscriptions[consumer][feed];
        emit LogSubscriptionTransferred(consumer, feed, newConsumer);
    }

    /// @inheritdoc ISubscriptionRegistry
    function isSubscribed(
        address consumer,
        address feed
    ) external view override returns (bool) {
        return _subscriptions[consumer][feed].dueTime > block.timestamp;
    }

    /// @inheritdoc ISubscriptionRegistry
    function getSubscriptionDueTime(
        address consumer,
        address feed
    ) external view override returns (uint256 dueTime) {
        dueTime = _subscriptions[consumer][feed].dueTime;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(ISubscriptionRegistry).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function _batchSubscribe(
        address[] calldata consumers,
        address feed,
        address owner,
        uint256 dueTime
    ) internal {
        for (uint256 i = 0; i < consumers.length; i++) {
            _subscribe(consumers[i], feed, owner, dueTime);
        }
    }

    function _subscribe(
        address consumer,
        address feed,
        address owner,
        uint256 dueTime
    ) internal {
        _subscriptions[consumer][feed] = Subscription(uint64(dueTime), owner);
        emit LogSubscribed(consumer, feed, owner, dueTime);
    }

    function _collectPayment(
        uint256 consumers,
        address feed,
        uint256 dueTime
    ) internal {
        uint256 price = PricingHelper.getPriceForTimespan(
            IFeed(feed).getPricePerSecondScaled(),
            dueTime - block.timestamp
        );
        uint256 totalPrice = price * consumers;

        _treasury.deposit(msg.sender, totalPrice);
    }

    function _checkSubscriptionData(
        address consumer,
        address feed,
        address owner,
        uint256 dueTime
    ) internal {
        require(consumer != address(0) && feed != address(0), ZeroAddress());
        require(
            dueTime >= block.timestamp + MIN_SUBSCRIPTION_TIME,
            WrongSubscriptionTime(dueTime)
        );
        require(
            IFeed(feed).getFeedType() == IFeed.FeedType.PUBLIC,
            NotPublicFeed(feed)
        );
    }

    function _checkSubscriptionData(
        address[] calldata consumers,
        address feed,
        address owner,
        uint256 dueTime
    ) internal view {
        require(consumers.length > 0, ZeroAddress());
        require(feed != address(0) && owner != address(0), ZeroAddress());
        require(
            dueTime >= block.timestamp + MIN_SUBSCRIPTION_TIME,
            WrongSubscriptionTime(dueTime)
        );
        require(
            IFeed(feed).getFeedType() == IFeed.FeedType.PUBLIC,
            NotPublicFeed(feed)
        );
    }
}
