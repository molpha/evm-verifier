// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {INodeRegistry} from "../../src/interfaces/INodeRegistry.sol";
import {INodeRegistryStructs} from "../../src/interfaces/INodeRegistryStructs.sol";
import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";

contract MockNodeRegistry is INodeRegistry {
    using LibSecp256k1 for LibSecp256k1.Point;

    mapping(address => bool) public nodes;
    uint256 public total;
    bytes32 public lastMessage;
    bool public verificationResult = true;

    function setLastMessage(bytes32 message) external {
        lastMessage = message;
    }

    function setVerificationResult(bool result) external {
        verificationResult = result;
    }

    function initialize(address accessControlManager) external override {}

    function initializeJob(bytes32, uint64) external override {}

    function getJobRound(bytes32) external pure override returns (uint32) {
        return 0;
    }

    function getJobSeed(bytes32) external pure override returns (bytes32) {
        return bytes32(0);
    }

    function getGroupSize(uint256 signaturesRequired) external pure override returns (uint256) {
        return signaturesRequired + 2;
    }

    function publish(
        INodeRegistryStructs.DataUpdate calldata,
        INodeRegistryStructs.SchnorrSignature calldata
    ) external pure override {}

    function verifySignature(
        bytes32 /*message*/,
        INodeRegistryStructs.SchnorrSignature calldata /*schnorrData*/,
        uint256 /*minSignaturesThreshold*/,
        uint32 /*round*/,
        bytes32 /*seed*/,
        uint256 /*nodeCount*/
    ) external override {
        if (!verificationResult) {
            revert("Verification failed");
        }
    }

    function addNode(bytes memory compressedPubKey, bytes memory) external override {
        LibSecp256k1.Point memory pubkey = LibSecp256k1.decompress(compressedPubKey);
        address node = pubkey.toAddress();
        nodes[node] = true;
        total += 1;
    }

    function removeNode(address node) external override {
        require(nodes[node], "not node");
        nodes[node] = false;
        total -= 1;
    }

    function isNode(address node) external view override returns (bool) {
        return nodes[node];
    }

    function getTotalNodes() external view override returns (uint256) {
        return total;
    }

    function getNodesSetHash() external pure override returns (bytes32) {
        return bytes32(0);
    }

    function participationCounts(uint256) external pure override returns (uint256) {
        return 0;
    }

    function getAggregateKey() external pure override returns (uint256, uint256) {
        return (0, 0);
    }

    function getNodeIndex(address /*node*/) external pure override returns (uint256 index) {
        return 0;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(INodeRegistry).interfaceId ||
               interfaceId == 0x01ffc9a7; // ERC165 interface ID
    }
}
