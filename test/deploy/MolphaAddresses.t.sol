// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test, console2} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {Verifier} from "../../src/Verifier.sol";
import {MolphaAddresses} from "../../src/consumer/MolphaAddresses.sol";
import {DeployConstants} from "../../script/libs/DeployConstants.sol";

/// @notice Keeps `MolphaAddresses`, `DeployConstants`, and `deployments.json` from drifting apart.
/// @dev Consumers pin `MolphaAddresses.VERIFIER`. That constant is only meaningful while every
///      ingredient behind it — factory, salt, creation code, constructor args — is a repo
///      invariant. This suite is what makes that true rather than aspirational.
contract MolphaAddressesPinTest is Test {
    using stdJson for string;

    string internal json;

    function setUp() public {
        json = vm.readFile("deployments.json");
    }

    // ---- Always-on: the ingredients must agree across all three sources ----

    function test_saltMatchesDeployConstants() public pure {
        assertEq(MolphaAddresses.VERIFIER_SALT, DeployConstants.VERIFIER_SALT, "salt");
    }

    function test_constructorArgsMatchDeployConstants() public pure {
        assertEq(MolphaAddresses.INITIAL_PROTOCOL_ADMIN, DeployConstants.PROTOCOL_ADMIN, "admin");
        assertEq(MolphaAddresses.INITIAL_REDUNDANCY_BUFFER, DeployConstants.REDUNDANCY_BUFFER, "buffer");
    }

    function test_deploymentsJsonMatchesLibrary() public view {
        assertEq(json.readBytes32(".verifier.salt"), MolphaAddresses.VERIFIER_SALT, "json salt");
        assertEq(json.readAddress(".verifier.create2Factory"), MolphaAddresses.CREATE2_FACTORY, "json factory");
        assertEq(
            json.readAddress(".verifier.initialProtocolAdmin"), MolphaAddresses.INITIAL_PROTOCOL_ADMIN, "json admin"
        );
        assertEq(
            json.readUint(".verifier.initialRedundancyBuffer"), MolphaAddresses.INITIAL_REDUNDANCY_BUFFER, "json buffer"
        );
        assertEq(json.readAddress(".verifier.address"), MolphaAddresses.VERIFIER, "json address");
        assertEq(json.readBytes32(".verifier.initCodeHash"), MolphaAddresses.VERIFIER_INIT_CODE_HASH, "json initCode");
    }

    /// @dev Every chain the record claims must carry the one canonical address.
    function test_deploymentsJsonChainsAllShareTheCanonicalAddress() public view {
        string[] memory chainIds = vm.parseJsonKeys(json, ".verifier.chains");
        for (uint256 i; i < chainIds.length; ++i) {
            assertEq(
                json.readAddress(string.concat(".verifier.chains.", chainIds[i])), MolphaAddresses.VERIFIER, chainIds[i]
            );
        }
    }

    // ---- The derivation itself, once a real address is published ----

    /// @dev Reports the address the current build would land on. A deployer reads this off CI to
    ///      fill in `MolphaAddresses.VERIFIER` and `deployments.json` for the audited release.
    function test_logPredictedAddressForCurrentBuild() public pure {
        (address predicted, bytes32 initCodeHash) = _predict();
        console2.log("initCodeHash (current build):", vm.toString(initCodeHash));
        console2.log("predicted VERIFIER          :", predicted);
    }

    function test_pinnedAddressDerivesFromPinnedIngredients() public {
        if (MolphaAddresses.VERIFIER == address(0)) {
            // PROVISIONAL: no deployment exists for this interface yet. The ingredient-parity
            // tests above still run; only the literal derivation is deferred.
            vm.skip(true);
        }
        (address predicted, bytes32 initCodeHash) = _predict();
        assertEq(MolphaAddresses.VERIFIER_INIT_CODE_HASH, initCodeHash, "init code hash drifted");
        assertEq(MolphaAddresses.VERIFIER, predicted, "verifier address drifted");
    }

    function _predict() private pure returns (address predicted, bytes32 initCodeHash) {
        initCodeHash = hashInitCode(
            type(Verifier).creationCode, abi.encode(DeployConstants.PROTOCOL_ADMIN, DeployConstants.REDUNDANCY_BUFFER)
        );
        predicted = vm.computeCreate2Address(MolphaAddresses.VERIFIER_SALT, initCodeHash, CREATE2_FACTORY);
    }
}
