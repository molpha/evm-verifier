// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test, console2} from "forge-std/Test.sol";
import {MessageHashUtils} from "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

import {NodeRegistry} from "../src/NodeRegistry.sol";
import {AccessControlManager} from "../src/AccessControlManager.sol";
import {LibSecp256k1} from "../src/libs/LibSecp256k1.sol";

/// @title NodeRegistryRemoveNodeGasTest
/// @notice Measures gas usage of a single `removeNode` call for different existing node counts.
///
/// Requested scenarios:
/// - totalNodes before remove: 0, 1, 16, 32, 64, 128, 256
///
/// Notes:
/// - For `0`, `removeNode` is expected to revert with "Not node".
/// - Setup is excluded from gas metering; only the measured `removeNode` call is counted.
///
/// Run:
///   forge test --match-path test/NodeRegistryRemoveNodeGas.t.sol -vv
contract NodeRegistryRemoveNodeGasTest is Test {
    using MessageHashUtils for bytes32;
    using LibSecp256k1 for LibSecp256k1.Point;

    bytes32 internal constant POP_DOMAIN = keccak256("MOLPHA_NODE_REGISTRATION_V1");

    function _secret(uint256 slot) internal pure returns (uint256) {
        return (uint256(keccak256(abi.encodePacked("MOLPHA_REMOVE_NODE_GAS_KEY", slot))) % (LibSecp256k1.Q() - 1)) + 1;
    }

    function _popSig(address registryAddr, bytes memory compressedPubKey, uint256 sk) internal pure returns (bytes memory) {
        bytes32 digest = keccak256(abi.encodePacked(POP_DOMAIN, registryAddr, compressedPubKey)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _newRegistry() internal returns (NodeRegistry reg) {
        AccessControlManager acl = new AccessControlManager();
        acl.initialize(address(this));
        acl.grantRole(acl.NODE_REGISTRY(), address(this));

        reg = new NodeRegistry();
        reg.initialize(address(acl));
    }

    function _populate(NodeRegistry reg, uint256 count) internal returns (address[] memory nodes) {
        nodes = new address[](count);
        for (uint256 i; i < count; ++i) {
            uint256 sk = _secret(i + 1);
            LibSecp256k1.Point memory pk = LibSecp256k1.mulAffine(LibSecp256k1.G(), sk);
            bytes memory compressed = LibSecp256k1.compress(pk);
            reg.addNode(compressed, _popSig(address(reg), compressed, sk));
            nodes[i] = pk.toAddress();
        }
    }

    function _measureRemoveAtExistingCount(uint256 existingCount) internal {
        vm.pauseGasMetering();
        NodeRegistry reg = _newRegistry();
        address[] memory nodes = _populate(reg, existingCount);
        vm.resumeGasMetering();

        if (existingCount == 0) {
            vm.expectRevert("Not node");
            reg.removeNode(address(0xBEEF));
            vm.pauseGasMetering();
            console2.log(
                string.concat(
                    "removeNode | totalNodesBefore=",
                    vm.toString(existingCount),
                    " | result=revert(Not node)"
                )
            );
            vm.resumeGasMetering();
            return;
        }

        // Remove the first node so we consistently exercise the "swap with last" path when len > 2.
        address victim = nodes[0];
        uint256 gasBefore = gasleft();
        reg.removeNode(victim);
        uint256 gasUsed = gasBefore - gasleft();

        vm.pauseGasMetering();
        console2.log(
            string.concat(
                "removeNode | totalNodesBefore=",
                vm.toString(existingCount),
                " | gasUsed=",
                vm.toString(gasUsed)
            )
        );
        vm.resumeGasMetering();
    }

    function test_gas_removeNode_requested_counts() public {
        _measureRemoveAtExistingCount(0);
        _measureRemoveAtExistingCount(1);
        _measureRemoveAtExistingCount(16);
        _measureRemoveAtExistingCount(32);
        _measureRemoveAtExistingCount(64);
        _measureRemoveAtExistingCount(128);
        _measureRemoveAtExistingCount(256);
    }
}
