// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {NodesAggregator} from "../src/NodesAggregator.sol";
import {INodesAggregator, INodesAggregatorErrors, INodesAggregatorStructs} from "../src/interfaces/INodesAggregator.sol";
import {LibSecp256k1} from "../src/libs/LibSecp256k1.sol";

contract NodeAggregatorTest is Test {
    using LibSecp256k1 for LibSecp256k1.Point;

    NodesAggregator agg;

    function setUp() public {
        agg = new NodesAggregator(address(this));
    }

    function test_registerNode_InvalidKey_Revert() public {
        LibSecp256k1.Point memory zero = LibSecp256k1.ZERO_POINT();
        vm.expectRevert(INodesAggregatorErrors.InvalidPublicKey.selector);
        agg.addNode(zero);
    }

    function test_registerAndUnregisterNode_Works() public {
        LibSecp256k1.Point memory g = LibSecp256k1.G();
        agg.addNode(g);
        assertTrue(agg.isNode(g.toAddress()));
        assertEq(agg.getTotalNodes(), 1);

        agg.removeNode(g.toAddress());
        assertFalse(agg.isNode(g.toAddress()));
        assertEq(agg.getTotalNodes(), 0);
    }

    function testFuzz_verifySignature_InvalidOrder(uint256 a, uint256 b) public {
        LibSecp256k1.Point memory g = LibSecp256k1.G();
        agg.addNode(g);
        uint256[] memory signers = new uint256[](2);
        signers[0] = 1;
        signers[1] = 1; // not strictly increasing
        INodesAggregatorStructs.SchnorrSignature memory s = INodesAggregatorStructs.SchnorrSignature({
            signature: bytes32(uint256(1)),
            commitment: address(1),
            signers: signers
        });
        bytes32 msgHash = keccak256(abi.encodePacked(a, b));
        vm.expectRevert(INodesAggregatorErrors.InvalidSignersOrder.selector);
        agg.verifySignature(msgHash, s, 1);
    }
}
