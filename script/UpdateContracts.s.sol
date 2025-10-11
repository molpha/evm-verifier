// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ProxyAdmin} from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {DataSourceRegistry} from "../src/DataSourceRegistry.sol";
import {FeedRegistry} from "../src/FeedRegistry.sol";
import {SubscriptionRegistry} from "../src/SubscriptionRegistry.sol";
import {NodeRegistry} from "../src/NodeRegistry.sol";
import {Treasury} from "../src/Treasury.sol";
import {PricingHelper} from "../src/PricingHelper.sol";
import {AccessControlManager} from "../src/AccessControlManager.sol";

contract UpdateContracts is Script {
    string private _addresses;

    constructor() {
        _addresses = string(abi.encodePacked("./addresses-", vm.toString(block.timestamp), "-update.json"));
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAdminAddress = vm.envAddress("PROXY_ADMIN");
        
        // Initialize the JSON file for new addresses
        vm.writeJson('{"addresses":{}}', _addresses);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementations
        address newDataSourceRegistryImpl = address(new DataSourceRegistry());
        address newFeedRegistryImpl = address(new FeedRegistry());
        address newSubscriptionRegistryImpl = address(new SubscriptionRegistry());
        address newNodeRegistryImpl = address(new NodeRegistry());
        address newTreasuryImpl = address(new Treasury(IERC20(vm.envAddress("USDC"))));
        address newPricingHelperImpl = address(new PricingHelper());
        address newAccessControlManagerImpl = address(new AccessControlManager());

        // Get ProxyAdmin instance
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);

        // Upgrade contracts if their proxy addresses are provided
        _upgradeIfProvided(proxyAdmin, "DataSourceRegistry", newDataSourceRegistryImpl, vm.envOr("DATA_SOURCE_REGISTRY_PROXY", address(0)));
        _upgradeIfProvided(proxyAdmin, "FeedRegistry", newFeedRegistryImpl, vm.envOr("FEED_REGISTRY_PROXY", address(0)));
        _upgradeIfProvided(proxyAdmin, "SubscriptionRegistry", newSubscriptionRegistryImpl, vm.envOr("SUBSCRIPTION_REGISTRY_PROXY", address(0)));
        _upgradeIfProvided(proxyAdmin, "NodeRegistry", newNodeRegistryImpl, vm.envOr("NODE_REGISTRY_PROXY", address(0)));
        _upgradeIfProvided(proxyAdmin, "Treasury", newTreasuryImpl, vm.envOr("TREASURY_PROXY", address(0)));
        _upgradeIfProvided(proxyAdmin, "PricingHelper", newPricingHelperImpl, vm.envOr("PRICING_HELPER_PROXY", address(0)));
        _upgradeIfProvided(proxyAdmin, "AccessControlManager", newAccessControlManagerImpl, vm.envOr("ACCESS_CONTROL_MANAGER_PROXY", address(0)));

        vm.stopBroadcast();

        console.log("Update completed! New addresses saved to:", _addresses);
    }

    function _upgradeIfProvided(
        ProxyAdmin proxyAdmin,
        string memory contractName,
        address newImplementation,
        address proxyAddress
    ) private {
        if (proxyAddress != address(0)) {
            proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(proxyAddress), newImplementation, "");
            console.log(contractName, "upgraded to:", newImplementation);
            
            // Save the new implementation address
            vm.writeJson(vm.serializeAddress("", contractName, newImplementation), _addresses, ".addresses");
        } else {
            console.log(contractName, "skipped - no proxy address provided");
        }
    }
} 