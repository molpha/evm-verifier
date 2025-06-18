// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";

import {INodesAggregator} from "../../src/interfaces/INodesAggregator.sol";
import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";

contract MockNodesAggregator is INodesAggregator, ERC165 {
    using LibSecp256k1 for LibSecp256k1.Point;

    mapping(address => bool) public nodes;
    uint256 public total;
    bytes32 public lastMessage;

    function setLastMessage(bytes32 message) external {
        lastMessage = message;
    }

    function verifySignature(
        bytes32 message,
        SchnorrSignature calldata schnorrData,
        uint256 minSignaturesThreshold
    ) external view {
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

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(INodesAggregator).interfaceId || super.supportsInterface(interfaceId);
    }
}
