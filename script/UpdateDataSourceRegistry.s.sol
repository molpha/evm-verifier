// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {ProxyAdmin} from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {DataSourceRegistry} from "../src/DataSourceRegistry.sol";

contract UpdateDataSourceRegistry is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAdminAddress = vm.envAddress("PROXY_ADMIN");
        address dataSourceRegistryProxy = vm.envAddress("DATA_SOURCE_REGISTRY_PROXY");
        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation
        address newImplementation = address(new DataSourceRegistry());
        
        // Get ProxyAdmin instance
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        
        // Upgrade the proxy to new implementation
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(dataSourceRegistryProxy), newImplementation, "");
        
        vm.stopBroadcast();
        
        // Log the new implementation address
        console.log("New DataSourceRegistry implementation deployed at:", newImplementation);
        console.log("Proxy upgraded successfully");
    }
} 