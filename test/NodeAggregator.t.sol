// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {NodeRegistry} from "../src/NodeRegistry.sol";
import {AccessControlManager} from "../src/AccessControlManager.sol";
import {INodeRegistry, INodeRegistryStructs} from "../src/interfaces/INodeRegistry.sol";
import {LibSecp256k1} from "../src/libs/LibSecp256k1.sol";
import {console} from "forge-std/console.sol";

contract NodeAggregatorTest is Test {
    using LibSecp256k1 for LibSecp256k1.Point;

    NodeRegistry registry;
    AccessControlManager acl;

    function setUp() public {
        registry = new NodeRegistry();
        acl = new AccessControlManager();
        
        // Initialize AccessControlManager with the test contract as admin
        acl.initialize(address(this));
        
        // Grant NODE_REGISTRY role to this test contract so it can call addNode/removeNode
        acl.grantRole(acl.NODE_REGISTRY(), address(this));
        
        // Initialize NodeRegistry
        registry.initialize(address(acl));
    }

    function test_registerNode_InvalidKeyLength_Revert() public {
        bytes memory zero = new bytes(0);
        vm.expectRevert("invalid length");
        registry.addNode(zero);
    }

    function test_registerAndUnregisterNode_Works() public {
        LibSecp256k1.Point memory g = LibSecp256k1.G();
        registry.addNode(LibSecp256k1.compress(g));
        assertTrue(registry.isNode(g.toAddress()));
        assertEq(registry.getTotalNodes(), 1);

        registry.removeNode(g.toAddress());
        assertFalse(registry.isNode(g.toAddress()));
        assertEq(registry.getTotalNodes(), 0);
    }

    function testFuzz_verifySignature_InvalidOrder(uint256 a, uint256 b) public {
        LibSecp256k1.Point memory g = LibSecp256k1.G();
        registry.addNode(LibSecp256k1.compress(g));
        uint256[] memory signers = new uint256[](2);
        signers[0] = 1;
        signers[1] = 1; // not strictly increasing
        INodeRegistryStructs.SchnorrSignature memory s = INodeRegistryStructs.SchnorrSignature({
            signature: bytes32(uint256(1)),
            commitment: address(1),
            signers: signers
        });
        bytes32 msgHash = keccak256(abi.encodePacked(a, b));
        vm.expectRevert("Invalid signers order");
        registry.verifySignature(msgHash, s, 1);
    }
}
