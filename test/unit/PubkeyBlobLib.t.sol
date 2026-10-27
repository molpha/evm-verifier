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

    function clear(bytes calldata encoded, uint256 index)
        external
        pure
        returns (bytes memory result, uint256 newLength)
    {
        result = encoded;
        newLength = result.clearPubkey(index);
    }

    function firstFreeSlot(bytes calldata encoded) external pure returns (uint256) {
        return bytes(encoded).firstFreeSlot();
    }

    function set(bytes calldata encoded, uint256 index, LibSecp256k1.Point calldata pubkey)
        external
        pure
        returns (bytes memory result)
    {
        result = encoded;
        result.setPubkey(index, pubkey);
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

    function test_clearPubkey_leavesAHoleInTheMiddleAndMovesNothing() public view {
        LibSecp256k1.Point[] memory points = new LibSecp256k1.Point[](4);
        points[0] = _point(10, 11);
        points[1] = _point(20, 21);
        points[2] = _point(30, 31);
        points[3] = _point(40, 41);

        (bytes memory result, uint256 newLength) = harness.clear(_encode(points), 2);

        assertEq(newLength, 4);
        assertEq(harness.length(result), 4);
        _assertPointEq(harness.get(result, 0), points[0]);
        _assertPointEq(harness.get(result, 1), points[1]);
        _assertPointEq(harness.get(result, 2), _point(0, 0));
        _assertPointEq(harness.get(result, 3), points[3]);
        assertEq(result, _encode(_withHole(points, 2)), "byte layout is a plain encoding with a zero point");
    }

    function test_clearPubkey_trimsTheLastPointAndTheHolesBehindIt() public view {
        LibSecp256k1.Point[] memory points = new LibSecp256k1.Point[](4);
        points[0] = _point(10, 11);
        points[1] = _point(20, 21);
        points[2] = _point(30, 31);
        points[3] = _point(40, 41);

        // Open holes at 1 and 2, then remove the last: all three trailing slots fall away.
        (bytes memory step1,) = harness.clear(_encode(points), 1);
        (bytes memory step2,) = harness.clear(step1, 2);
        (bytes memory step3, uint256 newLength) = harness.clear(step2, 3);

        assertEq(newLength, 1);
        assertEq(harness.length(step3), 1);
        _assertPointEq(harness.get(step3, 0), points[0]);

        LibSecp256k1.Point[] memory one = new LibSecp256k1.Point[](1);
        one[0] = points[0];
        assertEq(step3, _encode(one), "the byte-length word shrinks with the array");
    }

    function test_clearPubkey_removingTheOnlyPointEmptiesTheBlob() public view {
        LibSecp256k1.Point[] memory points = new LibSecp256k1.Point[](1);
        points[0] = _point(10, 11);

        (bytes memory result, uint256 newLength) = harness.clear(_encode(points), 0);

        assertEq(newLength, 0);
        assertEq(result, _encode(new LibSecp256k1.Point[](0)));
    }

    function test_firstFreeSlot_isTheLowestHoleElseTheLength() public view {
        LibSecp256k1.Point[] memory points = new LibSecp256k1.Point[](4);
        points[0] = _point(10, 11);
        points[1] = _point(20, 21);
        points[2] = _point(30, 31);
        points[3] = _point(40, 41);
        assertEq(harness.firstFreeSlot(_encode(points)), 4, "no hole: append position");

        assertEq(harness.firstFreeSlot(_encode(_withHole(_withHole(points, 3), 1))), 1, "lowest of two holes");
        assertEq(harness.firstFreeSlot(_encode(new LibSecp256k1.Point[](0))), 0, "empty blob");
        // A point with only one zero coordinate is not a hole.
        points[0] = _point(0, 11);
        assertEq(harness.firstFreeSlot(_encode(points)), 4);
    }

    function test_setPubkey_fillsAHoleWithoutDisturbingNeighbours() public view {
        LibSecp256k1.Point[] memory points = new LibSecp256k1.Point[](3);
        points[0] = _point(10, 11);
        points[1] = _point(20, 21);
        points[2] = _point(30, 31);
        bytes memory holed = _encode(_withHole(points, 1));

        bytes memory result = harness.set(holed, 1, _point(70, 71));

        assertEq(harness.length(result), 3);
        _assertPointEq(harness.get(result, 0), points[0]);
        _assertPointEq(harness.get(result, 1), _point(70, 71));
        _assertPointEq(harness.get(result, 2), points[2]);
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

    function _withHole(LibSecp256k1.Point[] memory points, uint256 index)
        internal
        pure
        returns (LibSecp256k1.Point[] memory out)
    {
        out = new LibSecp256k1.Point[](points.length);
        for (uint256 i; i < points.length; ++i) {
            out[i] = points[i];
        }
        out[index] = _point(0, 0);
    }
}
