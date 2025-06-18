// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFeedsFactory} from "../../src/interfaces/IFeedsFactory.sol";

contract MockFeedsFactory is IFeedsFactory {
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
}
