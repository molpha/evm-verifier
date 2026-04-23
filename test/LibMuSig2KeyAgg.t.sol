// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {NodeRegistry} from "../src/NodeRegistry.sol";
import {AccessControlManager} from "../src/AccessControlManager.sol";
import {LibSecp256k1} from "../src/libs/LibSecp256k1.sol";
import {LibMuSig2KeyAgg} from "../src/libs/LibMuSig2KeyAgg.sol";

contract LibMuSig2KeyAggTest is Test {
    using LibSecp256k1 for LibSecp256k1.Point;

    function test_aggregateKeys_singleGenerator_matchesLibrary() public pure {
        LibSecp256k1.Point memory g = LibSecp256k1.G();
        LibSecp256k1.Point[] memory one = new LibSecp256k1.Point[](1);
        one[0] = g;
        LibSecp256k1.Point memory agg = LibMuSig2KeyAgg.aggregateKeys(one);

        bytes32 L = keccak256(abi.encodePacked(bytes32(g.x), bytes32(g.y)));
        uint256 a = uint256(
            keccak256(abi.encodePacked(bytes("MOLPHA_MUSIG2_COEFF_V1"), bytes32(L), bytes32(g.x), bytes32(g.y)))
        ) % LibSecp256k1.Q();
        if (a == 0) a = 1;
        LibSecp256k1.Point memory expected = LibSecp256k1.mulAffine(g, a);
        assertEq(agg.x, expected.x);
        assertEq(agg.y, expected.y);
    }

    function test_registry_storedMuSig_matches_aggregateRegistryKeys() public {
        NodeRegistry registry = new NodeRegistry();
        AccessControlManager acl = new AccessControlManager();
        acl.initialize(address(this));
        acl.grantRole(acl.NODE_REGISTRY(), address(this));
        registry.initialize(address(acl));

        LibSecp256k1.Point memory g = LibSecp256k1.G();
        registry.addNode(LibSecp256k1.compress(g));

        (uint256 x, uint256 y) = registry.getMuSigAggregateKey();
        LibSecp256k1.Point[] memory reg = new LibSecp256k1.Point[](2);
        reg[0] = LibSecp256k1.ZERO_POINT();
        reg[1] = g;
        LibSecp256k1.Point memory expected = LibMuSig2KeyAgg.aggregateRegistryKeys(reg);
        assertEq(x, expected.x);
        assertEq(y, expected.y);
    }

    function test_computeEffectiveKeysAndAggregate_matchesAggregateRegistryKeys() public pure {
        LibSecp256k1.Point memory g = LibSecp256k1.G();
        LibSecp256k1.Point[] memory reg = new LibSecp256k1.Point[](2);
        reg[0] = LibSecp256k1.ZERO_POINT();
        reg[1] = g;

        (LibSecp256k1.Point[] memory eff, LibSecp256k1.Point memory agg) =
            LibMuSig2KeyAgg.computeEffectiveKeysAndAggregate(reg);

        LibSecp256k1.Point memory expectedAgg = LibMuSig2KeyAgg.aggregateRegistryKeys(reg);
        assertEq(agg.x, expectedAgg.x);
        assertEq(agg.y, expectedAgg.y);

        bytes32 Lreg = keccak256(abi.encodePacked(bytes32(g.x), bytes32(g.y)));
        uint256 a1 = uint256(
            keccak256(abi.encodePacked(bytes("MOLPHA_MUSIG2_COEFF_V1"), bytes32(Lreg), bytes32(g.x), bytes32(g.y)))
        ) % LibSecp256k1.Q();
        if (a1 == 0) a1 = 1;
        LibSecp256k1.Point memory e1 = LibSecp256k1.mulAffine(g, a1);
        assertEq(eff[1].x, e1.x);
        assertEq(eff[1].y, e1.y);
    }
}
