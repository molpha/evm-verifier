// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.31;

// import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
// import {ProxyAdmin} from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
// import {TransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
// import {Script} from "forge-std/Script.sol";

// import {LibSecp256k1} from "../src/libs/LibSecp256k1.sol";

// import {AccessControlManager} from "../src/AccessControlManager.sol";
// import {FeedRegistry} from "../src/FeedRegistry.sol";
// import {SubscriptionRegistry} from "../src/SubscriptionRegistry.sol";
// import {NodeRegistry} from "../src/NodeRegistry.sol";
// import {Treasury} from "../src/Treasury.sol";
// import {MockedUSDC} from "../src/mocks/MockedUSDC.sol";
// import {PricingHelper} from "../src/PricingHelper.sol";
// import {DataSourceRegistry} from "../src/DataSourceRegistry.sol";

// import {IAccessControlManager} from "../src/interfaces/IAccessControlManager.sol";
// import {IFeedRegistry} from "../src/interfaces/IFeedRegistry.sol";
// import {ISubscriptionRegistry} from "../src/interfaces/ISubscriptionRegistry.sol";
// import {INodeRegistry} from "../src/interfaces/INodeRegistry.sol";
// import {INodeRegistryStructs} from "../src/interfaces/INodeRegistryStructs.sol";
// import {ITreasury} from "../src/interfaces/ITreasury.sol";
// import {IPricingHelper} from "../src/interfaces/IPricingHelper.sol";
// import {IDataSourceRegistry} from "../src/interfaces/IDataSourceRegistry.sol";

// contract Deploy is Script {
//     string private _addresses;

//     uint64 private constant BASE_PRICE_PER_SECOND_SCALED = 5787037; // 0.5 * 1ed6 * SCALAR / 1 days;
//     uint64 private constant FREQUENCY_COEFFICIENT = 3000;
//     uint64 private constant SIGNERS_COEFFICIENT = 4000;
//     uint64 private constant REWARD_PERCENTAGE = 5000; // 50% in basis points (out of 10000)

//     /// @dev Human-readable folder names under `deployments/`; unknown chains use `chain-<id>`.
//     function _deploymentChainFolder(uint256 chainId) private pure returns (string memory) {
//         if (chainId == 1) return "ethereum";
//         if (chainId == 11155111) return "sepolia";
//         if (chainId == 31337) return "anvil";
//         if (chainId == 43113) return "avalanche-fuji";
//         if (chainId == 43114) return "avalanche";
//         if (chainId == 421614) return "arbitrum-sepolia";
//         if (chainId == 42161) return "arbitrum-one";
//         if (chainId == 97) return "bsc-testnet";
//         if (chainId == 56) return "bsc";
//         if (chainId == 51) return "xdc-apothem";
//         if (chainId == 84532) return "base-sepolia";
//         if (chainId == 8453) return "base";
//         if (chainId == 137) return "polygon";
//         if (chainId == 80002) return "polygon-amoy";
//         return string.concat("chain-", vm.toString(chainId));
//     }

//     /// @dev Writes under `deployments/<chain-name>/` so each chain keeps its own address files.
//     function _initAddressesFile() private {
//         string memory chainDir =
//             string.concat("./deployments/", _deploymentChainFolder(block.chainid));
//         vm.createDir(chainDir, true);
//         _addresses = string.concat(chainDir, "/addresses-", vm.toString(block.timestamp), ".json");
//     }

//     function run() external {
//         _initAddressesFile();

//         uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
//         // IERC20 usdc = IERC20(vm.envAddress("USDC"));

//         // Initialize the JSON file
//         vm.writeJson('{"addresses":{}}', _addresses);

//         vm.startBroadcast(deployerPrivateKey);
//                 IERC20 usdc = new MockedUSDC();
//         address protocolAdmin = vm.envAddress("PROTOCOL_ADMIN");
//         MockedUSDC(address(usdc)).mint(protocolAdmin, 1000000000000000000000000);
        

//         // deploy
//         address accessControlManagerImpl = address(new AccessControlManager());
//         address proxyAdmin = address(new ProxyAdmin(protocolAdmin));

//         vm.writeJson(vm.serializeAddress("", type(ProxyAdmin).name, proxyAdmin), _addresses, ".addresses");

//         address accessControlManager = _deployProxy(accessControlManagerImpl, proxyAdmin, type(AccessControlManager).name);

//         address treasuryImpl = address(new Treasury(usdc));
//         address feedRegistryImpl = address(new FeedRegistry());
//         address nodeRegistryImpl = address(new NodeRegistry());
//         address subscriptionRegistryImpl = address(new SubscriptionRegistry());
//         address pricingHelperImpl = address(new PricingHelper());
//         address dataSourceRegistryImpl = address(new DataSourceRegistry());

//         address treasury = _deployProxy(treasuryImpl, proxyAdmin, type(Treasury).name);
//         address feedRegistry = _deployProxy(feedRegistryImpl, proxyAdmin, type(FeedRegistry).name);
//         address subscriptionsRegistry = _deployProxy(subscriptionRegistryImpl, proxyAdmin, type(SubscriptionRegistry).name);
//         address nodesRegistry = _deployProxy(nodeRegistryImpl, proxyAdmin, type(NodeRegistry).name);
//         address pricingHelper = _deployProxy(pricingHelperImpl, proxyAdmin, type(PricingHelper).name);
//         address dataSourceRegistry = _deployProxy(dataSourceRegistryImpl, proxyAdmin, type(DataSourceRegistry).name);

//         // initialize AccessControlManager first
//         IAccessControlManager(accessControlManager).initialize(protocolAdmin);

//         // then set roles
//         IAccessControlManager acm = IAccessControlManager(accessControlManager);
//         acm.grantRole(acm.NODE_REGISTRY(), nodesRegistry);
//         acm.grantRole(acm.PRICE_MANAGER(), protocolAdmin);
//         acm.grantRole(acm.FEED_REGISTRY(), feedRegistry);
//         acm.grantRole(acm.SUBSCRIPTION_REGISTRY(), subscriptionsRegistry);

//         IFeedRegistry(feedRegistry).initialize(accessControlManager, subscriptionsRegistry, dataSourceRegistry);
//         ISubscriptionRegistry(subscriptionsRegistry).initialize(accessControlManager, treasury, pricingHelper);
//         IDataSourceRegistry(dataSourceRegistry).initialize(accessControlManager);
//         ITreasury(treasury).initialize(accessControlManager);
//         INodeRegistry(nodesRegistry).initialize(accessControlManager);
//         IPricingHelper(pricingHelper).initialize(
//             accessControlManager, 
//             BASE_PRICE_PER_SECOND_SCALED, 
//             FREQUENCY_COEFFICIENT, 
//             SIGNERS_COEFFICIENT, 
//             REWARD_PERCENTAGE
//         );

//         // add nodes
//         INodeRegistry(nodesRegistry).addNode(
//             LibSecp256k1.compress(LibSecp256k1.Point({
//                 x: 82736532059003432392633182570149173260984108975602191333563796533410150488363,
//                 y: 2731131244337076789200646755548802147998927235804584501361233088743417311918
//         })),
//             INodeRegistryStructs.SchnorrProof({signature: bytes32(0), commitment: address(0)})
//         );        
//         INodeRegistry(nodesRegistry).addNode(
//             LibSecp256k1.compress(LibSecp256k1.Point({
//                 x: 109662376061415432835526913144777084357352510490439677569664664666711661278731,
//                 y: 34102494233018474759018060484637241906514180523497146441995129757852262776403
//         })),
//             INodeRegistryStructs.SchnorrProof({signature: bytes32(0), commitment: address(0)})
//         );        
//         INodeRegistry(nodesRegistry).addNode(
//             LibSecp256k1.compress(LibSecp256k1.Point({
//                 x: 23291323678511451217772133928868366990746786347038015158807413032596505148183,
//                 y: 47168895393257141911376575107721994933540642533810868803586352809270883649069
//         })),
//             INodeRegistryStructs.SchnorrProof({signature: bytes32(0), commitment: address(0)})
//         );

//         vm.stopBroadcast();
//     }

//     function _deployProxy(
//         address logic,
//         address proxyAdmin,
//         string memory name
//     ) private returns (address) {
//         address proxy = address(new TransparentUpgradeableProxy(logic, proxyAdmin, new bytes(0)));
//         vm.writeJson(vm.serializeAddress("", name, proxy), _addresses, ".addresses");

//         return address(proxy);
//     }
// }
