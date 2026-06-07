// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.31;

import {Script} from "forge-std/Script.sol";
import {Verifier} from "../src/Verifier.sol";

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

    /// @dev Writes under `deployments/<chain-name>/` so each chain keeps its own address files.
    function _initAddressesFile() private {
        string memory chainDir = string.concat("./deployments/", _deploymentChainFolder(block.chainid));
        vm.createDir(chainDir, true);
        _addresses = string.concat(chainDir, "/addresses-", vm.toString(block.timestamp), ".json");
        vm.writeJson('{"addresses":{}}', _addresses);
    }

    function run() external returns (Verifier verifier) {
        _initAddressesFile();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        verifier = new Verifier(deployer, 2);

        vm.stopBroadcast();

        vm.writeJson(vm.serializeAddress("", type(Verifier).name, address(verifier)), _addresses, ".addresses");
        vm.writeJson(vm.serializeAddress("", "ProtocolAdmin", verifier.protocolAdmin()), _addresses, ".addresses");
    }
}
