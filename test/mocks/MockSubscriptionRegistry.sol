// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ISubscriptionRegistry} from "../../src/interfaces/ISubscriptionRegistry.sol";
import {IFeedRegistry} from "../../src/interfaces/IFeedRegistry.sol";
import {IFeed} from "../../src/interfaces/IFeed.sol";

contract MockSubscriptionRegistry is ISubscriptionRegistry {
    mapping(address => mapping(address => bool)) public subscribed;
    mapping(address => mapping(address => uint256)) public subscriptionDueTimes;
    mapping(address => uint256) public prices;
    mapping(address => mapping(address => bool)) public personalFeedAccess;
    mapping(address => mapping(address => bool)) public accessGranted;
    mapping(address => mapping(address => address)) public subscriptionOwners;
    uint256 public fee;
    IFeedRegistry internal _feedRegistry;

    function initialize(IFeedRegistry feedRegistry) external {
        _feedRegistry = feedRegistry;
    }

    function subscribe(address consumer, address feed, uint256 dueTime) external override {
        subscribed[consumer][feed] = true;
        subscriptionDueTimes[consumer][feed] = dueTime;
        subscriptionOwners[consumer][feed] = msg.sender;
    }

    function subscribe(address[] calldata consumers, address feed, uint256 dueTime) external override {
        for (uint256 i = 0; i < consumers.length; i++) {
            subscribed[consumers[i]][feed] = true;
            subscriptionDueTimes[consumers[i]][feed] = dueTime;
            subscriptionOwners[consumers[i]][feed] = msg.sender;
        }
    }

    function subscribe(address consumer, address feed, address owner, uint256 dueTime) external override {
        subscribed[consumer][feed] = true;
        subscriptionDueTimes[consumer][feed] = dueTime;
        subscriptionOwners[consumer][feed] = owner;
    }

    function subscribe(address[] calldata consumers, address feed, address owner, uint256 dueTime) external override {
        for (uint256 i = 0; i < consumers.length; i++) {
            subscribed[consumers[i]][feed] = true;
            subscriptionDueTimes[consumers[i]][feed] = dueTime;
            subscriptionOwners[consumers[i]][feed] = owner;
        }
    }

    function subscribePersonal(address feed, address owner, uint256 dueTime) external {
        subscribed[owner][feed] = true;
        subscriptionDueTimes[owner][feed] = dueTime;
        subscriptionOwners[owner][feed] = owner;
        personalFeedAccess[feed][owner] = true;
    }

    function extendSubscription(address consumer, address feed, uint256 dueTime) external override {
        subscriptionDueTimes[consumer][feed] = dueTime;
    }

    function unsubscribe(address feed, address consumer) external override {
        subscribed[consumer][feed] = false;
        subscriptionDueTimes[consumer][feed] = 0;
        personalFeedAccess[feed][consumer] = false;
    }

    function grantAccess(address consumer, address feed) external override {
        accessGranted[consumer][feed] = true;
    }

    function grantAccess(address[] calldata consumers, address feed) external override {
        for (uint256 i = 0; i < consumers.length; i++) {
            accessGranted[consumers[i]][feed] = true;
        }
    }

    function revokeAccess(address consumer, address feed) external override {
        accessGranted[consumer][feed] = false;
    }

    function revokeAccess(address[] calldata consumers, address feed) external override {
        for (uint256 i = 0; i < consumers.length; i++) {
            accessGranted[consumers[i]][feed] = false;
        }
    }

    function transferSubscription(address consumer, address feed, address newOwner) external override {
        subscriptionOwners[consumer][feed] = newOwner;
    }

    function isSubscribed(address user, address feed) external view override returns (bool) {
        return subscribed[user][feed] && subscriptionDueTimes[user][feed] > block.timestamp;
    }

    function getSubscriptionDueTime(address consumer, address feed) external view override returns (uint256) {
        return subscriptionDueTimes[consumer][feed];
    }

    // Additional methods from actual implementation
    function isAccessGranted(address consumer, address feed) external view returns (bool) {
        return accessGranted[consumer][feed] || personalFeedAccess[feed][consumer];
    }

    function getSubscriptionPrice(address feed) external view returns (uint256) {
        return prices[feed];
    }

    function grantPersonalFeedAccess(address consumer, address feed) external {
        personalFeedAccess[feed][consumer] = true;
    }

    function revokePersonalFeedAccess(address consumer, address feed) external {
        personalFeedAccess[feed][consumer] = false;
    }

    function hasPersonalFeedAccess(address consumer, address feed) external view returns (bool hasAccess) {
        return personalFeedAccess[feed][consumer];
    }

    function setSubscriptionPrice(address feed, uint128 newPrice) external {
        prices[feed] = newPrice;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(ISubscriptionRegistry).interfaceId ||
               interfaceId == 0x01ffc9a7; // ERC165 interface ID
    }
}
