// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AccessControlManager} from "../src/AccessControlManager.sol";
import {IAccessControlManager} from "../src/interfaces/IAccessControlManager.sol";
// import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";

contract AccessControlManagerTest is Test {
    AccessControlManager acl;
    
    address protocolAdmin = address(1);
    address feedManager = address(2);
    address nodeManager = address(3);
    address priceManager = address(4);
    address unauthorized = address(5);

    function setUp() public {
        acl = new AccessControlManager();
        acl.initialize(protocolAdmin);
    }

    function test_initialize_SetsProtocolAdmin() public {
        assertTrue(acl.hasRole(acl.ADMIN_ROLE(), protocolAdmin));
        assertTrue(acl.hasRole(acl.DEFAULT_ADMIN_ROLE(), protocolAdmin));
    }

    function test_initialize_CannotInitializeTwice() public {
        vm.expectRevert();
        acl.initialize(address(999));
    }

    function test_constants_AreCorrect() public {
        assertEq(acl.FEED_MANAGER(), keccak256("FEED_MANAGER"));
        assertEq(acl.NODE_MANAGER(), keccak256("NODE_MANAGER"));
        assertEq(acl.PRICE_MANAGER(), keccak256("PRICE_MANAGER"));
        assertEq(acl.ADMIN_ROLE(), acl.DEFAULT_ADMIN_ROLE());
    }

    function test_grantRole_FeedManager() public {
        vm.prank(protocolAdmin);
        acl.grantRole(acl.FEED_MANAGER(), feedManager);
        
        assertTrue(acl.hasRole(acl.FEED_MANAGER(), feedManager));
    }

    function test_grantRole_NodeManager() public {
        vm.prank(protocolAdmin);
        acl.grantRole(acl.NODE_MANAGER(), nodeManager);
        
        assertTrue(acl.hasRole(acl.NODE_MANAGER(), nodeManager));
    }

    function test_grantRole_PriceManager() public {
        vm.prank(protocolAdmin);
        acl.grantRole(acl.PRICE_MANAGER(), priceManager);
        
        assertTrue(acl.hasRole(acl.PRICE_MANAGER(), priceManager));
    }

    function test_grantRole_OnlyAdmin() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        acl.grantRole(acl.FEED_MANAGER(), feedManager);
    }

    function test_revokeRole_RemovesAccess() public {
        // Grant role first
        vm.prank(protocolAdmin);
        acl.grantRole(acl.FEED_MANAGER(), feedManager);
        assertTrue(acl.hasRole(acl.FEED_MANAGER(), feedManager));
        
        // Revoke role
        vm.prank(protocolAdmin);
        acl.revokeRole(acl.FEED_MANAGER(), feedManager);
        assertFalse(acl.hasRole(acl.FEED_MANAGER(), feedManager));
    }

    function test_renounceRole_AllowsSelfRevocation() public {
        // Grant role first
        vm.prank(protocolAdmin);
        acl.grantRole(acl.FEED_MANAGER(), feedManager);
        assertTrue(acl.hasRole(acl.FEED_MANAGER(), feedManager));
        
        // Self-renounce role
        vm.prank(feedManager);
        acl.renounceRole(acl.FEED_MANAGER(), feedManager);
        assertFalse(acl.hasRole(acl.FEED_MANAGER(), feedManager));
    }

    function test_verifyProtocolAdmin_Success() public {
        // Should not revert for protocol admin
        acl.verifyProtocolAdmin(protocolAdmin);
    }

    function test_verifyProtocolAdmin_Failure() public {
        vm.expectRevert();
        acl.verifyProtocolAdmin(unauthorized);
    }

    function test_verifyFeedManager_Success() public {
        vm.prank(protocolAdmin);
        acl.grantRole(acl.FEED_MANAGER(), feedManager);
        
        // Should not revert for feed manager
        acl.verifyFeedManager(feedManager);
    }

    function test_verifyFeedManager_Failure() public {
        vm.expectRevert();
        acl.verifyFeedManager(unauthorized);
    }

    function test_verifyNodeManager_Success() public {
        vm.prank(protocolAdmin);
        acl.grantRole(acl.NODE_MANAGER(), nodeManager);
        
        // Should not revert for node manager
        acl.verifyNodeManager(nodeManager);
    }

    function test_verifyNodeManager_Failure() public {
        vm.expectRevert();
        acl.verifyNodeManager(unauthorized);
    }

    function test_verifyPriceManager_Success() public {
        vm.prank(protocolAdmin);
        acl.grantRole(acl.PRICE_MANAGER(), priceManager);
        
        // Should not revert for price manager
        acl.verifyPriceManager(priceManager);
    }

    function test_verifyPriceManager_Failure() public {
        vm.expectRevert();
        acl.verifyPriceManager(unauthorized);
    }

    function test_hasRole_ReturnsCorrectValue() public {
        assertFalse(acl.hasRole(acl.FEED_MANAGER(), feedManager));
        
        vm.prank(protocolAdmin);
        acl.grantRole(acl.FEED_MANAGER(), feedManager);
        
        assertTrue(acl.hasRole(acl.FEED_MANAGER(), feedManager));
    }

    function test_getRoleAdmin_ReturnsDefaultAdminRole() public {
        assertEq(acl.getRoleAdmin(acl.FEED_MANAGER()), acl.DEFAULT_ADMIN_ROLE());
        assertEq(acl.getRoleAdmin(acl.NODE_MANAGER()), acl.DEFAULT_ADMIN_ROLE());
        assertEq(acl.getRoleAdmin(acl.PRICE_MANAGER()), acl.DEFAULT_ADMIN_ROLE());
    }

    function test_supportsInterface_AccessControlManager() public {
        assertTrue(acl.supportsInterface(type(IAccessControlManager).interfaceId));
    }

    function test_supportsInterface_AccessControl() public {
        // Test standard AccessControl interface ID
        assertTrue(acl.supportsInterface(0x7965db0b)); // AccessControl interface ID
    }

    function test_supportsInterface_ERC165() public {
        assertTrue(acl.supportsInterface(0x01ffc9a7)); // ERC165 interface ID
    }

    function test_supportsInterface_InvalidInterface() public {
        assertFalse(acl.supportsInterface(0x12345678));
    }

    function test_multipleRoles_SameUser() public {
        // Grant multiple roles to the same user
        vm.startPrank(protocolAdmin);
        acl.grantRole(acl.FEED_MANAGER(), feedManager);
        acl.grantRole(acl.NODE_MANAGER(), feedManager);
        acl.grantRole(acl.PRICE_MANAGER(), feedManager);
        vm.stopPrank();
        
        // Verify all roles
        acl.verifyFeedManager(feedManager);
        acl.verifyNodeManager(feedManager);
        acl.verifyPriceManager(feedManager);
        
        assertTrue(acl.hasRole(acl.FEED_MANAGER(), feedManager));
        assertTrue(acl.hasRole(acl.NODE_MANAGER(), feedManager));
        assertTrue(acl.hasRole(acl.PRICE_MANAGER(), feedManager));
    }

    function test_roleHierarchy_AdminCanDoEverything() public {
        // Protocol admin should be able to perform all verifications
        acl.verifyProtocolAdmin(protocolAdmin);
        
        // Admin can also grant themselves other roles
        vm.prank(protocolAdmin);
        acl.grantRole(acl.FEED_MANAGER(), protocolAdmin);
        acl.verifyFeedManager(protocolAdmin);
    }

    function test_grantRole_EmitsEvent() public {
        // Expect RoleGranted event to be emitted
        vm.expectEmit(true, true, true, true);
        
        vm.prank(protocolAdmin);
        acl.grantRole(acl.FEED_MANAGER(), feedManager);
    }

    function test_revokeRole_EmitsEvent() public {
        // Grant role first
        vm.prank(protocolAdmin);
        acl.grantRole(acl.FEED_MANAGER(), feedManager);
        
        // Expect RoleRevoked event to be emitted
        vm.expectEmit(true, true, true, true);
        
        vm.prank(protocolAdmin);
        acl.revokeRole(acl.FEED_MANAGER(), feedManager);
    }

    function test_adminRole_Function() public {
        assertEq(acl.ADMIN_ROLE(), acl.DEFAULT_ADMIN_ROLE());
    }

    function testFuzz_grantAndRevokeRole(address user, uint256 roleIndex) public {
        vm.assume(user != address(0));
        
        bytes32[] memory roles = new bytes32[](3);
        roles[0] = acl.FEED_MANAGER();
        roles[1] = acl.NODE_MANAGER();
        roles[2] = acl.PRICE_MANAGER();
        
        bytes32 role = roles[roleIndex % 3];
        
        // Initially should not have role
        assertFalse(acl.hasRole(role, user));
        
        // Grant role
        vm.prank(protocolAdmin);
        acl.grantRole(role, user);
        assertTrue(acl.hasRole(role, user));
        
        // Revoke role
        vm.prank(protocolAdmin);
        acl.revokeRole(role, user);
        assertFalse(acl.hasRole(role, user));
    }

    function test_multipleConcurrentUsers() public {
        address user1 = address(100);
        address user2 = address(101);
        address user3 = address(102);
        
        vm.startPrank(protocolAdmin);
        acl.grantRole(acl.FEED_MANAGER(), user1);
        acl.grantRole(acl.NODE_MANAGER(), user2);
        acl.grantRole(acl.PRICE_MANAGER(), user3);
        vm.stopPrank();
        
        // Each user should only have their specific role
        assertTrue(acl.hasRole(acl.FEED_MANAGER(), user1));
        assertFalse(acl.hasRole(acl.NODE_MANAGER(), user1));
        assertFalse(acl.hasRole(acl.PRICE_MANAGER(), user1));
        
        assertFalse(acl.hasRole(acl.FEED_MANAGER(), user2));
        assertTrue(acl.hasRole(acl.NODE_MANAGER(), user2));
        assertFalse(acl.hasRole(acl.PRICE_MANAGER(), user2));
        
        assertFalse(acl.hasRole(acl.FEED_MANAGER(), user3));
        assertFalse(acl.hasRole(acl.NODE_MANAGER(), user3));
        assertTrue(acl.hasRole(acl.PRICE_MANAGER(), user3));
        
        // Verify functions should work correctly
        acl.verifyFeedManager(user1);
        acl.verifyNodeManager(user2);
        acl.verifyPriceManager(user3);
    }
} 