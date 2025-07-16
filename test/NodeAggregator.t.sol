// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {NodeRegistry} from "../src/NodeRegistry.sol";
import {INodeRegistry, INodeRegistryErrors, INodeRegistryStructs} from "../src/interfaces/INodeRegistry.sol";
import {LibSecp256k1} from "../src/libs/LibSecp256k1.sol";

contract NodeAggregatorTest is Test {
    using LibSecp256k1 for LibSecp256k1.Point;

    NodeRegistry registry;

    function setUp() public {
        registry = new NodeRegistry();
        registry.initialize();
    }

    function test_registerNode_InvalidKey_Revert() public {
        LibSecp256k1.Point memory zero = LibSecp256k1.ZERO_POINT();
        vm.expectRevert(INodeRegistryErrors.InvalidPublicKey.selector);
        registry.addNode(zero);
    }

    function test_registerAndUnregisterNode_Works() public {
        LibSecp256k1.Point memory g = LibSecp256k1.G();
        registry.addNode(g);
        assertTrue(registry.isNode(g.toAddress()));
        assertEq(registry.getTotalNodes(), 1);

        registry.removeNode(g.toAddress());
        assertFalse(registry.isNode(g.toAddress()));
        assertEq(registry.getTotalNodes(), 0);
    }

    function testFuzz_verifySignature_InvalidOrder(uint256 a, uint256 b) public {
        LibSecp256k1.Point memory g = LibSecp256k1.G();
        registry.addNode(g);
        uint256[] memory signers = new uint256[](2);
        signers[0] = 1;
        signers[1] = 1; // not strictly increasing
        INodeRegistryStructs.SchnorrSignature memory s = INodeRegistryStructs.SchnorrSignature({
            signature: bytes32(uint256(1)),
            commitment: address(1),
            signers: signers
        });
        bytes32 msgHash = keccak256(abi.encodePacked(a, b));
        vm.expectRevert(INodeRegistryErrors.InvalidSignersOrder.selector);
        registry.verifySignature(msgHash, s, 1);
    }
}
