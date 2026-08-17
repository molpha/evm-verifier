// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.31;

import {Script, console2} from "forge-std/Script.sol";
import {Verifier} from "../src/Verifier.sol";
import {DeployConstants} from "./libs/DeployConstants.sol";

error Create2AddressMismatch();

contract Deploy is Script {
    string private _addresses;

    /// @dev Human-readable folder names under `deployments/`; unknown chains use `chain-<id>`.
    function _deploymentChainFolder(uint256 chainId) private pure returns (string memory) {
        if (chainId == 1) return "ethereum";
        if (chainId == 11155111) return "sepolia";
        if (chainId == 31337) return "anvil";
        if (chainId == 43113) return "avalanche-fuji";
        if (chainId == 43114) return "avalanche";
        if (chainId == 421614) return "arbitrum-sepolia";
        if (chainId == 42161) return "arbitrum-one";
        if (chainId == 97) return "bsc-testnet";
        if (chainId == 56) return "bsc";
        if (chainId == 51) return "xdc-apothem";
        if (chainId == 84532) return "base-sepolia";
        if (chainId == 8453) return "base";
        if (chainId == 137) return "polygon";
        if (chainId == 80002) return "polygon-amoy";
        return string.concat("chain-", vm.toString(chainId));
    }

    /// @dev Writes under `deployments/<chain-name>/addresses.json`.
    function _initAddressesFile() private {
        string memory chainDir = string.concat("./deployments/", _deploymentChainFolder(block.chainid));
        vm.createDir(chainDir, true);
        _addresses = string.concat(chainDir, "/addresses.json");
        vm.writeJson('{"addresses":{}}', _addresses);
    }

    function _salt() private view returns (bytes32) {
        if (vm.envExists("DEPLOY_SALT")) {
            return vm.envBytes32("DEPLOY_SALT");
        }
        return DeployConstants.VERIFIER_SALT;
    }

    function _predictVerifierAddress(address protocolAdmin, bytes32 salt)
        private
        pure
        returns (address predicted, bytes32 initCodeHash)
    {
        bytes memory constructorArgs = abi.encode(protocolAdmin, DeployConstants.REDUNDANCY_BUFFER);
        initCodeHash = hashInitCode(type(Verifier).creationCode, constructorArgs);
        // Foundry routes `new Contract{salt:}` through Arachnid's deterministic deployment proxy.
        predicted = vm.computeCreate2Address(salt, initCodeHash, CREATE2_FACTORY);
    }

    function run() external returns (Verifier verifier) {
        _initAddressesFile();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        bytes32 salt = _salt();

        (address predicted, bytes32 initCodeHash) = _predictVerifierAddress(deployer, salt);

        console2.log("Deployer:", deployer);
        console2.log("Salt:", vm.toString(salt));
        console2.log("Init code hash:", vm.toString(initCodeHash));
        console2.log("Predicted Verifier:", predicted);

        address deployed = predicted;
        if (predicted.code.length == 0) {
            vm.startBroadcast(deployerPrivateKey);
            verifier = new Verifier{salt: salt}(deployer, DeployConstants.REDUNDANCY_BUFFER);
            vm.stopBroadcast();
            deployed = address(verifier);
            if (deployed != predicted) revert Create2AddressMismatch();
            console2.log("Deployed Verifier:", deployed);
        } else {
            console2.log("Verifier already deployed at predicted address");
            verifier = Verifier(deployed);
        }

        string memory deploymentMeta = "deployment";
        vm.writeJson(vm.serializeString(deploymentMeta, "method", "CREATE2"), _addresses, ".deployment");
        vm.writeJson(vm.serializeBytes32(deploymentMeta, "salt", salt), _addresses, ".deployment");
        vm.writeJson(vm.serializeBytes32(deploymentMeta, "initCodeHash", initCodeHash), _addresses, ".deployment");
        vm.writeJson(vm.serializeAddress(deploymentMeta, "deployer", deployer), _addresses, ".deployment");
        vm.writeJson(vm.serializeAddress(deploymentMeta, "create2Factory", CREATE2_FACTORY), _addresses, ".deployment");
        vm.writeJson(vm.serializeAddress(deploymentMeta, "predictedAddress", predicted), _addresses, ".deployment");
        vm.writeJson(vm.serializeUint(deploymentMeta, "chainId", block.chainid), _addresses, ".deployment");

        vm.writeJson(vm.serializeAddress("", type(Verifier).name, deployed), _addresses, ".addresses");
        vm.writeJson(vm.serializeAddress("", "ProtocolAdmin", verifier.owner()), _addresses, ".addresses");
    }
}
