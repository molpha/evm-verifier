// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";
import {MessageHashUtils} from "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {NodeRegistry} from "../src/NodeRegistry.sol";
import {AccessControlManager} from "../src/AccessControlManager.sol";
import {LibSecp256k1} from "../src/libs/LibSecp256k1.sol";
import {LibMuSig2KeyAgg} from "../src/libs/LibMuSig2KeyAgg.sol";

contract LibMuSig2KeyAggTest is Test {
    using LibSecp256k1 for LibSecp256k1.Point;
    using MessageHashUtils for bytes32;
    bytes32 internal constant POP_DOMAIN = keccak256("MOLPHA_NODE_REGISTRATION_V1");

    function _popSig(address registryAddr, bytes memory compressedPubKey, uint256 sk) internal view returns (bytes memory) {
        bytes32 digest = keccak256(abi.encodePacked(POP_DOMAIN, registryAddr, compressedPubKey)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sk, digest);
        return abi.encodePacked(r, s, v);
    }

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

    function test_registry_storedAggregate_isPlainSum() public {
        NodeRegistry registry = new NodeRegistry();
        AccessControlManager acl = new AccessControlManager();
        acl.initialize(address(this));
        acl.grantRole(acl.NODE_REGISTRY(), address(this));
        registry.initialize(address(acl));

        LibSecp256k1.Point memory g = LibSecp256k1.G();
        bytes memory compressed = LibSecp256k1.compress(g);
        registry.addNode(compressed, _popSig(address(registry), compressed, 1));

        (uint256 x, uint256 y) = registry.getAggregateKey();
        LibSecp256k1.Point memory expected = g;
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
