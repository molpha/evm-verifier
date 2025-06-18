// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFeedsRegistry} from "../../src/interfaces/IFeedsRegistry.sol";
import {IFeedsFactory} from "../../src/interfaces/IFeedsFactory.sol";

contract MockFeedsRegistry is IFeedsRegistry {
    mapping(address => bool) public feeds;
    IFeedsFactory public factory;

    function createFeed(bytes32, uint256, uint128, uint256) external returns (address feed) {
        feed = address(0);
    }

    function setSubscriptionPrice(address, uint128) external {}

    function isFeed(address addr) external view returns (bool) {
        return feeds[addr];
    }

    function getFeedsFactory() external view returns (IFeedsFactory) {
        return factory;
    }

    function addFeed(address feed) external {
        feeds[feed] = true;
    }
}
