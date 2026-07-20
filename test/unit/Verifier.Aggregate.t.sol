// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";
import {VerifierTestBase} from "../shared/VerifierTestBase.sol";

contract VerifierAggregateTest is VerifierTestBase {
    using LibSecp256k1 for LibSecp256k1.Point;

    function _add(uint256 secret) internal returns (LibSecp256k1.Point memory pubkey) {
        pubkey = LibSecp256k1.mulAffine(LibSecp256k1.G(), secret);
        bytes memory compressed = LibSecp256k1.compress(pubkey);
        verifier.addNode(compressed, _proofOfPossession(address(verifier), compressed, secret));
    }

    function _assertAgg(LibSecp256k1.Point memory expected) internal view {
        (uint256 x, uint256 y) = verifier.getAggregateKey();
        assertEq(x, expected.x);
        assertEq(y, expected.y);
        if (!(x == 0 && y == 0)) assertTrue(LibSecp256k1.Point({x: x, y: y}).isOnCurve());
    }

    function test_aggregate_addAfterInfinity() public {
        uint256 s1 = _secret(1);
        _add(s1);
        _add(LibSecp256k1.Q() - s1);
        _assertAgg(LibSecp256k1.ZERO_POINT());

        LibSecp256k1.Point memory p3 = _add(_secret(3));
        _assertAgg(p3);
    }

    function test_aggregate_removeAfterInfinity() public {
        uint256 s1 = _secret(1);
        LibSecp256k1.Point memory p1 = _add(s1);
        LibSecp256k1.Point memory p2 = _add(LibSecp256k1.Q() - s1);
        LibSecp256k1.Point memory p3 = _add(_secret(3));

        verifier.removeNode(p3.toAddress());
        _assertAgg(LibSecp256k1.ZERO_POINT());

        verifier.removeNode(p2.toAddress());
        _assertAgg(p1);
    }

    /// @dev New node key equals the current aggregate -> EC doubling.
    function test_aggregate_addNodeEqualToAggregate() public {
        uint256 sA = _secret(11);
        uint256 sB = _secret(12);
        _add(sA);
        _add(sB);

        uint256 sSum = addmod(sA, sB, LibSecp256k1.Q());
        LibSecp256k1.Point memory pSum = _add(sSum);

        // aggregate = A + B + (A+B) = 2*(A+B)
        _assertAgg(LibSecp256k1.mulAffine(pSum, 2));
    }

    /// @dev Aggregate equals the negation of the removed key -> EC doubling on removal.
    function test_aggregate_removeNodeWhenAggregateEqualsNegatedKey() public {
        uint256 sB = _secret(21);
        uint256 sA = LibSecp256k1.Q() - mulmod(2, sB, LibSecp256k1.Q());
        LibSecp256k1.Point memory pA = _add(sA); // A = -2B
        LibSecp256k1.Point memory pB = _add(sB);

        // aggregate = A + B = -B; removing B adds -B again -> doubling -> -2B = A
        verifier.removeNode(pB.toAddress());
        _assertAgg(pA);
    }

    function test_aggregate_removeLastNodeYieldsInfinity() public {
        LibSecp256k1.Point memory p = _add(_secret(31));
        verifier.removeNode(p.toAddress());
        _assertAgg(LibSecp256k1.ZERO_POINT());
    }
}
