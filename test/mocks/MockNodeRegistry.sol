// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {INodeRegistry} from "../../src/interfaces/INodeRegistry.sol";
import {INodeRegistryStructs} from "../../src/interfaces/INodeRegistryStructs.sol";
import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";

contract MockNodeRegistry is INodeRegistry {
    using LibSecp256k1 for LibSecp256k1.Point;

    mapping(address => bool) public nodes;
    uint256 public total;
    bytes32 public lastMessage;

    function setLastMessage(bytes32 message) external {
        lastMessage = message;
    }

    function verifySignature(
        bytes32 message,
        INodeRegistryStructs.SchnorrSignature calldata schnorrData,
        uint256 minSignaturesThreshold
    ) external view {
        // Mock implementation - store the message for testing
    }

    function addNode(LibSecp256k1.Point memory pubkey) external {
        address node = pubkey.toAddress();
        nodes[node] = true;
        total += 1;
    }

    function removeNode(address node) external {
        require(nodes[node], "not node");
        nodes[node] = false;
        total -= 1;
    }

    function isNode(address node) external view returns (bool) {
        return nodes[node];
    }

    function getTotalNodes() external view returns (uint256) {
        return total;
    }

    function getNodesSetHash() external pure returns (bytes32) {
        return bytes32(0);
    }

    function getNodeIndex(address node) external view override returns (uint256 index) {
        return 0;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(INodeRegistry).interfaceId ||
               interfaceId == 0x01ffc9a7; // ERC165 interface ID
    }
}
