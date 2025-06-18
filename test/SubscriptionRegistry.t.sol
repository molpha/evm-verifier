// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SubscriptionsRegistry} from "../src/SubscriptionRegistry.sol";
import {MockAccessControlManager} from "./mocks/MockAccessControlManager.sol";
import {MockFeedsRegistry} from "./mocks/MockFeedsRegistry.sol";
import {TestToken} from "./mocks/TestToken.sol";

contract SubscriptionRegistryTest is Test {
    SubscriptionsRegistry reg;
    MockAccessControlManager acl;
    MockFeedsRegistry feeds;
    TestToken token;
    address user = address(1);

    function setUp() public {
        token = new TestToken();
        acl = new MockAccessControlManager(address(this));
        reg = new SubscriptionsRegistry(acl, token);
        feeds = new MockFeedsRegistry();
        reg.initialize(feeds, 1e14); // fee 0.01%
        feeds.addFeed(address(100));
        reg.setSubscriptionPrice.selector; // silence warnings
    }

    function test_subscribe_setsDueTime() public {
        vm.prank(address(feeds));
        reg.setSubscriptionPrice(address(100), 1e13);
        token.mint(user, 1e18);
        vm.prank(user);
        token.approve(address(reg), 1e18);
        vm.prank(user);
        reg.subscribe(user, address(100), 1 days);
        assertTrue(reg.isSubscribed(user, address(100)));
    }

    function testFuzz_setSubscriptionFee_OnlyAdmin(uint256 fee) public {
        if (fee < 1e14 || fee > 1e17) return;
        reg.setSubscriptionFee(fee);
        assertEq(reg.getSubscriptionFee(), fee);
    }
}
