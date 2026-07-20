// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.31;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Verifier} from "../src/Verifier.sol";
import {IVerifier} from "../src/interfaces/IVerifier.sol";
import {LibSecp256k1} from "../src/libs/LibSecp256k1.sol";
import {PopSignLib} from "./libs/PopSignLib.sol";

bytes32 constant POP_DOMAIN = keccak256("MOLPHA_VALIDATOR_V1");

error NoNodesInFile();
error PrivateKeyNotProtocolAdmin();

/// @title AddNode
/// @notice Register one or more oracle nodes on a deployed `Verifier`.
/// @dev Env:
///      - `VERIFIER` (required): verifier contract address
///      - `PRIVATE_KEY` (required): protocol admin key for broadcast
///      - `NODES_FILE` (optional): JSON batch file (see README)
///      - or single-node env: `NODE_PRIVATE_KEY` or `COMPRESSED_PUBKEY` + `POP_SIGNATURE` + `POP_COMMITMENT`
contract AddNode is Script {
    using LibSecp256k1 for LibSecp256k1.Point;
    using stdJson for string;

    struct NodeCred {
        bytes compressedPubKey;
        IVerifier.SchnorrProof pop;
    }

    function run() external {
        address verifierAddr = vm.envAddress("VERIFIER");
        Verifier verifier = Verifier(verifierAddr);
        NodeCred[] memory nodes = _loadNodes(verifierAddr);

        console2.log("Verifier:", verifierAddr);
        console2.log("Registering nodes:", nodes.length);
        console2.log("Nodes before:", verifier.getTotalNodes());

        uint256 adminKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(adminKey);
        if (verifier.protocolAdmin() != admin) revert PrivateKeyNotProtocolAdmin();
        vm.startBroadcast(adminKey);

        for (uint256 i = 0; i < nodes.length; ++i) {
            LibSecp256k1.Point memory pubkey = LibSecp256k1.decompress(nodes[i].compressedPubKey);
            address node = pubkey.toAddress();
            console2.log("--- node", i);
            console2.log("  address:", node);
            verifier.addNode(nodes[i].compressedPubKey, nodes[i].pop);
            console2.log("  index:", verifier.getNodeIndex(node));
        }

        vm.stopBroadcast();

        console2.log("Nodes after:", verifier.getTotalNodes());
        console2.log("Registry version:", verifier.getRegistryVersion());
    }

    function _loadNodes(address verifierAddr) private view returns (NodeCred[] memory nodes) {
        if (vm.envExists("NODES_FILE")) {
            return _loadNodesFromFile(vm.envString("NODES_FILE"), verifierAddr);
        }

        nodes = new NodeCred[](1);
        nodes[0] = _loadSingleNode(verifierAddr);
    }

    function _loadNodesFromFile(string memory path, address verifierAddr)
        private
        view
        returns (NodeCred[] memory nodes)
    {
        string memory json = vm.readFile(path);

        if (json.keyExists(".privateKeys")) {
            uint256[] memory privateKeys = json.readUintArray(".privateKeys");
            nodes = new NodeCred[](privateKeys.length);
            for (uint256 i = 0; i < privateKeys.length; ++i) {
                nodes[i] = _fromPrivateKey(verifierAddr, privateKeys[i]);
            }
            return nodes;
        }

        uint256 count;
        while (json.keyExists(string.concat(".nodes[", vm.toString(count), "]"))) {
            ++count;
        }
        if (count == 0) revert NoNodesInFile();

        nodes = new NodeCred[](count);
        for (uint256 i = 0; i < count; ++i) {
            string memory base = string.concat(".nodes[", vm.toString(i), "]");
            if (json.keyExists(string.concat(base, ".privateKey"))) {
                nodes[i] = _fromPrivateKey(verifierAddr, json.readUint(string.concat(base, ".privateKey")));
            } else {
                nodes[i].compressedPubKey = json.readBytes(string.concat(base, ".compressedPubKey"));
                nodes[i].pop = IVerifier.SchnorrProof({
                    signature: json.readBytes32(string.concat(base, ".popSignature")),
                    commitment: json.readAddress(string.concat(base, ".popCommitment"))
                });
            }
        }
    }

    function _loadSingleNode(address verifierAddr) private view returns (NodeCred memory node) {
        if (vm.envExists("NODE_PRIVATE_KEY")) {
            return _fromPrivateKey(verifierAddr, vm.envUint("NODE_PRIVATE_KEY"));
        }

        node.compressedPubKey = vm.envBytes("COMPRESSED_PUBKEY");
        node.pop = IVerifier.SchnorrProof({
            signature: vm.envBytes32("POP_SIGNATURE"), commitment: vm.envAddress("POP_COMMITMENT")
        });
    }

    function _fromPrivateKey(address verifierAddr, uint256 nodeSk) private pure returns (NodeCred memory node) {
        LibSecp256k1.Point memory pubkey = LibSecp256k1.mulAffine(LibSecp256k1.G(), nodeSk);
        node.compressedPubKey = LibSecp256k1.compress(pubkey);

        bytes32 digest = keccak256(abi.encodePacked(POP_DOMAIN, verifierAddr, node.compressedPubKey));
        (bytes32 sig, address cmt) = PopSignLib.sign(pubkey, nodeSk, digest, 0);
        node.pop = IVerifier.SchnorrProof({signature: sig, commitment: cmt});
    }
}
