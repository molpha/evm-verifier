// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {ProxyAdmin} from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {SubscriptionRegistry} from "../src/SubscriptionRegistry.sol";

contract UpdateSubscriptionRegistry is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAdminAddress = 0xdcB82119e06B9A061a9F90aaFdd4C0691796Df92;
        address subscriptionRegistryProxy = 0x14d272D8F25A9B653C43A48ae054a44BE420126c;
        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation
        address newImplementation = address(new SubscriptionRegistry());
        
        // Get ProxyAdmin instance
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        
        // Upgrade the proxy to new implementation
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(subscriptionRegistryProxy), newImplementation, "");
        
        vm.stopBroadcast();
        
        // Log the new implementation address
        console.log("New SubscriptionRegistry implementation deployed at:", newImplementation);
        console.log("Proxy upgraded successfully");
        console.log("Proxy address:", subscriptionRegistryProxy);
        console.log("ProxyAdmin address:", proxyAdminAddress);
    }
}
