// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";

import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";
import {PubkeyBlobLib} from "../../src/libs/PubkeyBlobLib.sol";

contract PubkeyBlobHarness {
    using PubkeyBlobLib for bytes;

    function add(bytes calldata encoded, LibSecp256k1.Point calldata pubkey)
        external
        pure
        returns (bytes memory result)
    {
        result = encoded;
        result.addPubkey(pubkey);
    }

    function remove(bytes calldata encoded, uint256 index)
        external
        pure
        returns (bytes memory result, bool orderChanged)
    {
        result = encoded;
        orderChanged = result.removePubkey(index);
    }

    function get(bytes calldata encoded, uint256 index) external pure returns (LibSecp256k1.Point memory) {
        return bytes(encoded).getNode(index);
    }

    function length(bytes calldata encoded) external pure returns (uint256) {
        return bytes(encoded).getNodesLength();
    }
}

contract PubkeyBlobLibTest is Test {
    PubkeyBlobHarness internal harness = new PubkeyBlobHarness();

    function _point(uint256 x, uint256 y) internal pure returns (LibSecp256k1.Point memory) {
        return LibSecp256k1.Point({x: x, y: y});
    }

    function _encode(LibSecp256k1.Point[] memory points) internal pure returns (bytes memory) {
        return abi.encode(points);
    }

    function _assertPointEq(LibSecp256k1.Point memory actual, LibSecp256k1.Point memory expected) internal pure {
        assertEq(actual.x, expected.x);
        assertEq(actual.y, expected.y);
    }

    function test_getNodesLengthAndGetNode_decodeAbiEncodedArray() public view {
        LibSecp256k1.Point[] memory points = new LibSecp256k1.Point[](2);
        points[0] = _point(1, 2);
        points[1] = _point(3, 4);
        bytes memory encoded = _encode(points);

        assertEq(harness.length(encoded), 2);
        _assertPointEq(harness.get(encoded, 0), points[0]);
        _assertPointEq(harness.get(encoded, 1), points[1]);
    }

    function test_removePubkey_swapsLastPointIntoMiddleIndex() public view {
        LibSecp256k1.Point[] memory points = new LibSecp256k1.Point[](4);
        points[0] = _point(10, 11);
        points[1] = _point(20, 21);
        points[2] = _point(30, 31);
        points[3] = _point(40, 41);

        (bytes memory result, bool orderChanged) = harness.remove(_encode(points), 2);

        assertTrue(orderChanged);
        assertEq(harness.length(result), 3);
        _assertPointEq(harness.get(result, 0), points[0]);
        _assertPointEq(harness.get(result, 1), points[1]);
        _assertPointEq(harness.get(result, 2), points[3]);
    }

    function test_removePubkey_removesLastPointWithoutChangingOrder() public view {
        LibSecp256k1.Point[] memory points = new LibSecp256k1.Point[](3);
        points[0] = _point(10, 11);
        points[1] = _point(20, 21);
        points[2] = _point(30, 31);

        (bytes memory result, bool orderChanged) = harness.remove(_encode(points), 2);

        assertFalse(orderChanged);
        assertEq(harness.length(result), 2);
        _assertPointEq(harness.get(result, 0), points[0]);
        _assertPointEq(harness.get(result, 1), points[1]);
    }

    function test_addPubkey_appendsWithoutDisturbingExistingPoints() public view {
        LibSecp256k1.Point[] memory points = new LibSecp256k1.Point[](2);
        points[0] = _point(10, 11);
        points[1] = _point(20, 21);
        LibSecp256k1.Point memory appended = _point(60, 61);

        bytes memory result = harness.add(_encode(points), appended);

        assertEq(harness.length(result), 3);
        _assertPointEq(harness.get(result, 0), points[0]);
        _assertPointEq(harness.get(result, 1), points[1]);
        _assertPointEq(harness.get(result, 2), appended);
    }
}
