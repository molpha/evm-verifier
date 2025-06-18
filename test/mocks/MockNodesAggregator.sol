// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {INodesAggregator} from "../../src/interfaces/INodesAggregator.sol";
import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";

contract MockNodesAggregator is INodesAggregator {
    using LibSecp256k1 for LibSecp256k1.Point;

    mapping(address => bool) public nodes;
    uint256 public total;
    bytes32 public lastMessage;

    function verifySignature(bytes32 message, SchnorrSignature calldata, uint256) external {
        lastMessage = message;
    }

    function registerNode(LibSecp256k1.Point memory pubkey) external {
        address node = pubkey.toAddress();
        nodes[node] = true;
        total += 1;
    }

    function unregisterNode(address node) external {
        require(nodes[node], "not node");
        nodes[node] = false;
        total -= 1;
    }

    function isNode(address node) external view returns (bool) {
        return nodes[node];
    }

    function getTotalSigners() external view returns (uint256) {
        return total;
    }

    function getSignerSetHash() external pure returns (bytes32) {
        return bytes32(0);
    }
}
