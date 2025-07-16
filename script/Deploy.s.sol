// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ProxyAdmin} from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Script} from "forge-std/Script.sol";

import {AccessControlManager} from "../src/AccessControlManager.sol";
import {FeedRegistry} from "../src/FeedRegistry.sol";
import {SubscriptionRegistry} from "../src/SubscriptionRegistry.sol";
import {NodeRegistry} from "../src/NodeRegistry.sol";
import {Treasury} from "../src/Treasury.sol";
import {MockedUSDC} from "../src/mocks/MockedUSDC.sol";

import {IAccessControlManager} from "../src/interfaces/IAccessControlManager.sol";
import {IFeedRegistry} from "../src/interfaces/IFeedRegistry.sol";
import {ISubscriptionRegistry} from "../src/interfaces/ISubscriptionRegistry.sol";
import {INodeRegistry} from "../src/interfaces/INodeRegistry.sol";
import {ITreasury} from "../src/interfaces/ITreasury.sol";

contract Deploy is Script {
    string private _addresses;

    constructor() {
        // Use a simpler approach - write to the current directory or a relative path
        _addresses = string(abi.encodePacked("./addresses-", vm.toString(block.timestamp), ".json"));
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        IERC20 usdc = IERC20(vm.envAddress("USDC"));
        address protocolAdmin = vm.envAddress("PROTOCOL_ADMIN");
        
        // Initialize the JSON file
        vm.writeJson('{"addresses":{}}', _addresses);

        vm.startBroadcast(deployerPrivateKey);

        // deploy
        address accessControlManagerImpl = address(new AccessControlManager());
        address proxyAdmin = address(new ProxyAdmin(protocolAdmin));

        vm.writeJson(vm.serializeAddress("", type(ProxyAdmin).name, proxyAdmin), _addresses, ".addresses");

        address accessControlManager = _deployProxy(accessControlManagerImpl, proxyAdmin, type(AccessControlManager).name);

        address treasuryImpl = address(new Treasury(usdc));
        address feedRegistryImpl = address(new FeedRegistry());
        address nodeRegistryImpl = address(new NodeRegistry());
        address subscriptionRegistryImpl = address(new SubscriptionRegistry());

        address treasury = _deployProxy(treasuryImpl, proxyAdmin, type(Treasury).name);
        address feedRegistry = _deployProxy(feedRegistryImpl, proxyAdmin, type(FeedRegistry).name);
        address subscriptionsRegistry = _deployProxy(subscriptionRegistryImpl, proxyAdmin, type(SubscriptionRegistry).name);
        address nodesRegistry = _deployProxy(nodeRegistryImpl, proxyAdmin, type(NodeRegistry).name);

        // initialize AccessControlManager first
        IAccessControlManager(accessControlManager).initialize(protocolAdmin);

        // then set roles
        IAccessControlManager(accessControlManager).grantRole(IAccessControlManager(accessControlManager).NODE_REGISTRY(), nodesRegistry);
        IAccessControlManager(accessControlManager).grantRole(IAccessControlManager(accessControlManager).PRICE_MANAGER(), protocolAdmin);
        IFeedRegistry(feedRegistry).initialize(accessControlManager, subscriptionsRegistry);
        ISubscriptionRegistry(subscriptionsRegistry).initialize(accessControlManager, feedRegistry, treasury);
        ITreasury(treasury).initialize(accessControlManager);
        INodeRegistry(nodesRegistry).initialize();

        vm.stopBroadcast();
    }

    function _deployProxy(
        address logic,
        address proxyAdmin,
        string memory name
    ) private returns (address) {
        address proxy = address(new TransparentUpgradeableProxy(logic, proxyAdmin, new bytes(0)));
        vm.writeJson(vm.serializeAddress("", name, proxy), _addresses, ".addresses");

        return address(proxy);
    }
}
