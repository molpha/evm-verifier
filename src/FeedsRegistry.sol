// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";

import {ERC165Checker} from "./libs/ERC165Checker.sol";
import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {IFeed} from "./interfaces/IFeed.sol";
import {IFeedsFactory} from "./interfaces/IFeedsFactory.sol";
import {IFeedsRegistry} from "./interfaces/IFeedsRegistry.sol";
import {ISubscriptionsRegistry} from "./interfaces/ISubscriptionsRegistry.sol";
// import {ITreasury} from "./interfaces/ITreasury.sol";

contract FeedsRegistry is IFeedsRegistry, ERC165 {
    using ERC165Checker for address;

    // TODO: reconsider min and max reward
    uint256 internal constant MIN_REWARD = 1e16; // 0.01
    uint256 internal constant MAX_REWARD = 5e17; // 0.5

    IAccessControlManager internal immutable _accessControlManager;

    IFeedsFactory internal _feedsFactory;
    ISubscriptionsRegistry internal _subscriptionsRegistry;
    // ITreasury internal _treasury;

    address[] internal _feeds; // do we need this? the only use case is getFeeds()
    mapping(address => bool) internal _isFeed;

    constructor(IAccessControlManager accessControlManager) {
        address(accessControlManager).shouldSupport(type(IAccessControlManager).interfaceId);

        _accessControlManager = accessControlManager;
    }

    function initialize(
        IFeedsFactory feedsFactory,
        ISubscriptionsRegistry subscriptionsRegistry
        // ITreasury treasury
    ) external {
        if (address(_feedsFactory) != address(0)) {
            revert("AlreadyInitialized()");
        }
        address(feedsFactory).shouldSupport(type(IFeedsFactory).interfaceId);
        address(subscriptionsRegistry).shouldSupport(type(ISubscriptionsRegistry).interfaceId);
        // address(treasury).shouldSupport(type(ITreasury).interfaceId);

        _feedsFactory = feedsFactory;
        _subscriptionsRegistry = subscriptionsRegistry;
        // _treasury = treasury;
    }

    modifier onlyFeedsManager() {
       _accessControlManager.verifyFeedsManager(msg.sender);
        _;
    }

    /// @inheritdoc IFeedsRegistry
    function createFeed(
        bytes32 metadataHash, 
        uint256 minSignaturesThreshold
    )
        external
        override
        onlyFeedsManager
        returns (address feed)
    {
        // _validateReward(rewardForAnswer);

        feed = _feedsFactory.build();
        _feeds.push(feed);
        _isFeed[feed] = true;
        IFeed(feed).initialize(metadataHash, minSignaturesThreshold);

        emit LogFeedCreated(feed);

        // _treasury.setRewardForAnswer(feed, rewardForAnswer);
        // _subscriptionsRegistry.setSubscriptionPrice(feed, subscriptionPrice);/
    }

    // /// @inheritdoc IFeedsRegistry
    // function setAggregatorReward(address aggregator, uint256 reward) external override onlyAggregatorsManager {
    //     _validateAggregator(aggregator);
    //     _validateReward(reward);

    //     _treasury.setRewardForAnswer(aggregator, reward);
    // }

    // function setSubscriptionPrice(address feed, uint128 price)
    //     external
    //     override
    //     onlyFeedsManager
    // {
    //     _validateFeed(feed);

    //     _subscriptionsRegistry.setSubscriptionPrice(feed, price);
    //     emit LogSubscriptionPriceChanged(feed, price);
    // }

    /// @inheritdoc IFeedsRegistry
    function isFeed(address feed) external view override returns (bool) {
        return _isFeed[feed];
    }

    // /// @inheritdoc IFeedsRegistry
    // function getAggregators() external view override returns (address[] memory) {
    //     return _aggregators;
    // }

    /// @inheritdoc IFeedsRegistry
    function getFeedsFactory() external view override returns (IFeedsFactory) {
        return _feedsFactory;
    }

    // /// @inheritdoc IFeedsRegistry
    // function getTreasury() external view override returns (ITreasury) {
    //     return _treasury;
    // }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IFeedsRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    // function _validateReward(uint256 reward) internal pure {
    //     // reward can be 0, we may have only own nodes and don't need to pay for answers
    //     if (reward != 0 && (reward < MIN_REWARD || reward > MAX_REWARD)) {
    //         revert WrongReward(reward);
    //     }
    // }

    function _validateFeed(address feed) internal view {
        if (!_isFeed[feed]) {
            revert NotFeed(feed);
        }
    }
}
