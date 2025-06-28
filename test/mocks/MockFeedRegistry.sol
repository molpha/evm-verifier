// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";

import {IFeedRegistry} from "../../src/interfaces/IFeedRegistry.sol";
import {IFeedFactory} from "../../src/interfaces/IFeedFactory.sol";

contract MockFeedRegistry is IFeedRegistry, ERC165 {
    mapping(address => bool) public feeds;
    IFeedFactory public factory;

    function createFeed(bytes32, uint256) external returns (address feed) {
        feed = address(0);
    }

    function isFeed(address addr) external view returns (bool) {
        return feeds[addr];
    }

    function getFeedFactory() external view returns (IFeedFactory) {
        return factory;
    }

    function addFeed(address feed) external {
        feeds[feed] = true;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IFeedRegistry).interfaceId || super.supportsInterface(interfaceId);
    }
}
