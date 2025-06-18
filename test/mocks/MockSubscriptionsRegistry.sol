// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISubscriptionsRegistry} from "../../src/interfaces/ISubscriptionsRegistry.sol";

contract MockSubscriptionsRegistry is ISubscriptionsRegistry {
    mapping(address => bool) public subscribed;
    uint256 public price;
    uint256 public fee;

    function subscribe(address consumer, address, uint256) external {
        subscribed[consumer] = true;
    }

    function unsubscribe(address) external {
        subscribed[msg.sender] = false;
    }

    function setSubscriptionPrice(address, uint128 newPrice) external {
        price = newPrice;
    }

    function setSubscriptionFee(uint256 newFee) external {
        fee = newFee;
    }

    function isSubscribed(address user, address) external view returns (bool) {
        return subscribed[user];
    }

    function getSubscriptionPrice(address) external view returns (uint256) {
        return price;
    }

    function getSubscriptionFee() external view returns (uint256) {
        return fee;
    }

    function getSubscriptionDueTime(address, address) external pure returns (uint256) {
        return 0;
    }
}
