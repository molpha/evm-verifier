// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test, console2} from "forge-std/Test.sol";
import {MessageHashUtils} from "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

import {NodeRegistry} from "../src/NodeRegistry.sol";
import {AccessControlManager} from "../src/AccessControlManager.sol";
import {LibSecp256k1} from "../src/libs/LibSecp256k1.sol";

/// @title NodeRegistryAddNodeGasTest
/// @notice Measures gas usage of a single `addNode` call for different existing node counts.
///
/// Requested scenarios:
/// - totalNodes before add: 0, 1, 16, 32, 64, 128, 256
///
/// Notes:
/// - For `256`, `addNode` is expected to revert with "Max nodes reached".
/// - Setup is excluded from gas metering; only the measured `addNode` call is counted.
///
/// Run:
///   forge test --match-path test/NodeRegistryAddNodeGas.t.sol -vv
contract NodeRegistryAddNodeGasTest is Test {
    using MessageHashUtils for bytes32;

    bytes32 internal constant POP_DOMAIN = keccak256("MOLPHA_NODE_REGISTRATION_V1");

    function _secret(uint256 slot) internal pure returns (uint256) {
        return (uint256(keccak256(abi.encodePacked("MOLPHA_ADD_NODE_GAS_KEY", slot))) % (LibSecp256k1.Q() - 1)) + 1;
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

    function _populate(NodeRegistry reg, uint256 count) internal {
        for (uint256 i; i < count; ++i) {
            uint256 sk = _secret(i + 1);
            LibSecp256k1.Point memory pk = LibSecp256k1.mulAffine(LibSecp256k1.G(), sk);
            bytes memory compressed = LibSecp256k1.compress(pk);
            reg.addNode(compressed, _popSig(address(reg), compressed, sk));
        }
    }

    function _measureAddAtExistingCount(uint256 existingCount) internal {
        vm.pauseGasMetering();
        NodeRegistry reg = _newRegistry();
        _populate(reg, existingCount);

        uint256 newSk = _secret(existingCount + 1);
        LibSecp256k1.Point memory newPk = LibSecp256k1.mulAffine(LibSecp256k1.G(), newSk);
        bytes memory newCompressed = LibSecp256k1.compress(newPk);
        bytes memory newPop = _popSig(address(reg), newCompressed, newSk);
        vm.resumeGasMetering();

        if (existingCount == 256) {
            vm.expectRevert("Max nodes reached");
            reg.addNode(newCompressed, newPop);
            vm.pauseGasMetering();
            console2.log(
                string.concat(
                    "addNode | totalNodesBefore=",
                    vm.toString(existingCount),
                    " | result=revert(Max nodes reached)"
                )
            );
            vm.resumeGasMetering();
            return;
        }

        uint256 gasBefore = gasleft();
        reg.addNode(newCompressed, newPop);
        uint256 gasUsed = gasBefore - gasleft();

        vm.pauseGasMetering();
        console2.log(
            string.concat(
                "addNode | totalNodesBefore=",
                vm.toString(existingCount),
                " | gasUsed=",
                vm.toString(gasUsed)
            )
        );
        vm.resumeGasMetering();
    }

    function test_gas_addNode_requested_counts() public {
        _measureAddAtExistingCount(0);
        _measureAddAtExistingCount(1);
        _measureAddAtExistingCount(16);
        _measureAddAtExistingCount(32);
        _measureAddAtExistingCount(64);
        _measureAddAtExistingCount(128);
        _measureAddAtExistingCount(255);
    }
}
