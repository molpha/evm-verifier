// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISubscriptionRegistry} from "../../src/interfaces/ISubscriptionRegistry.sol";

contract MockSubscriptionRegistry is ISubscriptionRegistry {
    mapping(address => mapping(address => bool)) public subscribed;
    mapping(address => uint256) public prices;
    uint256 public fee;

    function subscribe(address consumer, address feed, uint256) external {
        subscribed[consumer][feed] = true;
    }

    function unsubscribe(address feed, address consumer) external {
        subscribed[consumer][feed] = false;
    }

    function setSubscriptionPrice(address feed, uint128 newPrice) external {
        prices[feed] = newPrice;
    }

    function setSubscriptionFee(uint256 newFee) external {
        fee = newFee;
    }

    function isSubscribed(address user, address feed) external view returns (bool) {
        return subscribed[user][feed];
    }

    function getSubscriptionPrice(address feed) external view returns (uint256) {
        return prices[feed];
    }

    function getSubscriptionFee() external view returns (uint256) {
        return fee;
    }

    function getSubscriptionDueTime(address consumer, address feed) external view returns (uint256) {
        return block.timestamp + 30 days;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(ISubscriptionRegistry).interfaceId ||
               interfaceId == 0x01ffc9a7; // ERC165 interface ID
    }
}
