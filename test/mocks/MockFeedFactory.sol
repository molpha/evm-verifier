// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";

import {IFeedFactory} from "../../src/interfaces/IFeedFactory.sol";
contract MockFeedFactory is IFeedFactory, ERC165 {
    address public implementation;

    function build() external returns (address) {
        address impl = implementation;
        // deploy minimal proxy to keep simple - for testing return implementation directly
        return impl;
    }

    function setAggregatorImpl(address impl) external {
        implementation = impl;
    }

    function getAggregatorImpl() external view returns (address) {
        return implementation;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IFeedFactory).interfaceId || super.supportsInterface(interfaceId);
    }
}
