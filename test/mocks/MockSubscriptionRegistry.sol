// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ISubscriptionRegistry} from "../../src/interfaces/ISubscriptionRegistry.sol";

contract MockSubscriptionRegistry is ISubscriptionRegistry {
    mapping(address => mapping(address => bool)) public subscriptions;
    mapping(address => mapping(address => Subscription)) public subscriptionData;
    mapping(address => mapping(address => uint256)) public subscriptionDueTimes;

    // ISubscriptionRegistry interface implementation
    function initialize(address accessControlManager, address feedRegistry, address treasury) external {
        // Mock implementation - no actual initialization needed
    }

    function subscribe(address feed, uint256 dueTime, address[] calldata consumers) external {
        for (uint256 i = 0; i < consumers.length; i++) {
            subscriptions[consumers[i]][feed] = true;
            subscriptionDueTimes[consumers[i]][feed] = dueTime;
            subscriptionData[consumers[i]][feed] = Subscription({
                dueTime: uint64(dueTime),
                owner: msg.sender
            });
        }
    }

    function initFeedSubscription(address feed, address owner, uint256 dueTime, address[] calldata consumers) external {
        subscriptions[owner][feed] = true;
        subscriptionDueTimes[owner][feed] = dueTime;
        subscriptionData[owner][feed] = Subscription({
            dueTime: uint64(dueTime),
            owner: owner
        });

        for (uint256 i = 0; i < consumers.length; i++) {
            subscriptions[consumers[i]][feed] = true;
            subscriptionDueTimes[consumers[i]][feed] = dueTime;
            subscriptionData[consumers[i]][feed] = Subscription({
                dueTime: uint64(dueTime),
                owner: owner
            });
        }
    }

    function extendSubscription(address consumer, address feed, uint256 dueTime) external {
        subscriptions[consumer][feed] = true;
        subscriptionDueTimes[consumer][feed] = dueTime;
        subscriptionData[consumer][feed].dueTime = uint64(dueTime);
    }

    function unsubscribe(address feed, address consumer) external {
        subscriptions[consumer][feed] = false;
        subscriptionDueTimes[consumer][feed] = 0;
        subscriptionData[consumer][feed].dueTime = 0;
    }

    function transferSubscription(address consumer, address feed, address newConsumer) external {
        subscriptions[newConsumer][feed] = subscriptions[consumer][feed];
        subscriptionDueTimes[newConsumer][feed] = subscriptionDueTimes[consumer][feed];
        subscriptionData[newConsumer][feed] = subscriptionData[consumer][feed];
        
        subscriptions[consumer][feed] = false;
        subscriptionDueTimes[consumer][feed] = 0;
        delete subscriptionData[consumer][feed];
    }

    function recalculateSubscription(address feed) external {
        // Mock implementation
    }

    function setConsumerPricePerSecondScaled(address feed, uint256 consumerPricePerSecondScaled) external {
        // Mock implementation
    }
    function setFeedRegistry(address feedRegistry) external {
        // Mock implementation
    }

    function setTreasury(address treasury) external {
        // Mock implementation
    }

    function getSubscription(address consumer, address feed) external view returns (Subscription memory subscription) {
        return subscriptionData[consumer][feed];
    }

    function isSubscribed(address consumer, address feed) external view returns (bool) {
        return subscriptions[consumer][feed] && subscriptionDueTimes[consumer][feed] > block.timestamp;
    }

    // Helper functions for testing
    function setSubscribed(address consumer, address feed, bool subscribed) external {
        subscriptions[consumer][feed] = subscribed;
        if (subscribed) {
            subscriptionDueTimes[consumer][feed] = block.timestamp + 30 days;
            subscriptionData[consumer][feed] = Subscription({
                dueTime: uint64(block.timestamp + 30 days),
                owner: msg.sender
            });
        } else {
            subscriptionDueTimes[consumer][feed] = 0;
            subscriptionData[consumer][feed].dueTime = 0;
        }
    }

    function setSubscriptionDueTime(address consumer, address feed, uint256 dueTime) external {
        subscriptionDueTimes[consumer][feed] = dueTime;
        subscriptionData[consumer][feed].dueTime = uint64(dueTime);
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(ISubscriptionRegistry).interfaceId || interfaceId == 0x01ffc9a7; // ERC165
    }
}
