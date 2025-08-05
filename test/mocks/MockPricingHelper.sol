// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IPricingHelper} from "../../src/interfaces/IPricingHelper.sol";
import {IERC165} from "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

contract MockPricingHelper is IPricingHelper {
    function calculatePrice(address) external pure returns (uint256) {
        return 1;
    }

    function getPriceForTimespan(uint256 pricePerSecondScaled, uint256 timespan) external pure returns (uint256) {
        return pricePerSecondScaled * timespan;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IPricingHelper).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
} 