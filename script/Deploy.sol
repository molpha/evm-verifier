// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {AccessControlManager} from "../src/AccessControlManager.sol";
import {FeedRegistry} from "../src/FeedRegistry.sol";
import {SubscriptionRegistry} from "../src/SubscriptionRegistry.sol";
import {NodeRegistry} from "../src/NodeRegistry.sol";
import {MockedUSDC} from "../src/mocks/MockedUSDC.sol";

/**
 * @title Deploy
 * @notice Deployment script for Molpha core contracts
 * @dev Deploys AccessControlManager, NodeRegistry, SubscriptionRegistry, and FeedRegistry
 *      with proper initialization and role setup
 */
contract Deploy is Script {
    // Chain configurations
    uint256 constant AVALANCHE_FUJI = 43113;
    uint256 constant AVALANCHE_MAINNET = 43114;
    uint256 constant ETHEREUM_MAINNET = 1;
    uint256 constant ETHEREUM_SEPOLIA = 11155111;

    // Known USDC addresses on different chains
    mapping(uint256 => address) public knownUSDC;

    // Deployment configuration
    struct DeploymentConfig {
        uint256 chainId;
        uint256 deployerKey;
        address protocolAdmin;
        address feedManager;
        address nodeManager;
        address priceManager;
        address nodeRegistryOwner;
        address usdcToken;
        bool useExistingUSDC;
    }

    // Deployed contracts
    struct DeployedContracts {
        AccessControlManager accessControlManager;
        NodeRegistry nodeRegistry;
        SubscriptionRegistry subscriptionRegistry;
        FeedRegistry feedRegistry;
        IERC20 usdcToken;
    }

    constructor() {
        // Initialize known USDC addresses
        knownUSDC[AVALANCHE_MAINNET] = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E; // USDC on Avalanche
        knownUSDC[ETHEREUM_MAINNET] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC on Ethereum
        // Fuji testnet doesn't have official USDC, so we'll deploy MockedUSDC
        knownUSDC[AVALANCHE_FUJI] = address(0);
        knownUSDC[ETHEREUM_SEPOLIA] = address(0);
    }

    function run() external returns (DeployedContracts memory) {
        // Get configuration from environment or use defaults
        DeploymentConfig memory config = getDeploymentConfig();
        
        console.log("=== Molpha Protocol Deployment ===");
        console.log("Chain ID:", config.chainId);
        console.log("Protocol Admin:", config.protocolAdmin);
        console.log("Node Registry Owner:", config.nodeRegistryOwner);
        
        vm.startBroadcast(config.deployerKey);
        
        DeployedContracts memory contracts = deployContracts(config);
        
        vm.stopBroadcast();
        
        // Log deployed addresses
        logDeployedAddresses(contracts);
        
        return contracts;
    }

    function deployContracts(DeploymentConfig memory config) internal returns (DeployedContracts memory contracts) {
        console.log("\n=== Deploying Contracts ===");
        
        // 1. Deploy or get USDC token
        contracts.usdcToken = deployOrGetUSDC(config);
        console.log("USDC Token:", address(contracts.usdcToken));
        
        // 2. Deploy AccessControlManager
        contracts.accessControlManager = new AccessControlManager();
        console.log("AccessControlManager deployed:", address(contracts.accessControlManager));
        
        // 3. Initialize AccessControlManager
        contracts.accessControlManager.initialize(config.protocolAdmin);
        console.log("AccessControlManager initialized with admin:", config.protocolAdmin);
        
        // 4. Deploy NodeRegistry
        contracts.nodeRegistry = new NodeRegistry(config.nodeRegistryOwner);
        console.log("NodeRegistry deployed:", address(contracts.nodeRegistry));
        
        // 5. Deploy SubscriptionRegistry
        contracts.subscriptionRegistry = new SubscriptionRegistry(
            contracts.accessControlManager,
            contracts.usdcToken
        );
        console.log("SubscriptionRegistry deployed:", address(contracts.subscriptionRegistry));
        
        // 6. Deploy FeedRegistry
        contracts.feedRegistry = new FeedRegistry(
            contracts.accessControlManager,
            contracts.subscriptionRegistry,
            contracts.nodeRegistry
        );
        console.log("FeedRegistry deployed:", address(contracts.feedRegistry));
        
        // 7. Initialize SubscriptionRegistry with FeedRegistry
        contracts.subscriptionRegistry.initialize(contracts.feedRegistry);
        console.log("SubscriptionRegistry initialized with FeedRegistry");
        
        // 8. Setup roles and permissions
        setupRoles(contracts.accessControlManager, config);
        
        return contracts;
    }

    function deployOrGetUSDC(DeploymentConfig memory config) internal returns (IERC20) {
        if (config.useExistingUSDC && config.usdcToken != address(0)) {
            console.log("Using existing USDC at:", config.usdcToken);
            return IERC20(config.usdcToken);
        }
        
        address knownAddress = knownUSDC[config.chainId];
        if (knownAddress != address(0)) {
            console.log("Using known USDC address for chain:", config.chainId);
            return IERC20(knownAddress);
        }
        
        // Deploy MockedUSDC for testnets or when no known address exists
        console.log("Deploying MockedUSDC for testing");
        MockedUSDC mockUSDC = new MockedUSDC();
        
        // Mint some tokens to the deployer for testing
        mockUSDC.mintUSDC(msg.sender, 1000000); // 1M USDC
        console.log("Minted 1M USDC to deployer:", msg.sender);
        
        return IERC20(address(mockUSDC));
    }

    function setupRoles(AccessControlManager acl, DeploymentConfig memory config) internal {
        console.log("\n=== Setting up Roles ===");
        
        // Grant FEED_MANAGER role
        if (config.feedManager != address(0) && config.feedManager != config.protocolAdmin) {
            acl.grantRole(acl.FEED_MANAGER(), config.feedManager);
            console.log("Granted FEED_MANAGER role to:", config.feedManager);
        }
        
        // Grant NODE_MANAGER role  
        if (config.nodeManager != address(0) && config.nodeManager != config.protocolAdmin) {
            acl.grantRole(acl.NODE_MANAGER(), config.nodeManager);
            console.log("Granted NODE_MANAGER role to:", config.nodeManager);
        }
        
        // Grant PRICE_MANAGER role
        if (config.priceManager != address(0) && config.priceManager != config.protocolAdmin) {
            acl.grantRole(acl.PRICE_MANAGER(), config.priceManager);
            console.log("Granted PRICE_MANAGER role to:", config.priceManager);
        }
        
        console.log("Role setup completed");
    }

    function getDeploymentConfig() internal view returns (DeploymentConfig memory config) {
        // Get chain ID
        config.chainId = vm.envOr("CHAIN_ID", AVALANCHE_FUJI);
        config.deployerKey = vm.envUint("DEPLOYER");

        // Get addresses from environment variables or use msg.sender as fallback
        config.protocolAdmin = vm.envOr("PROTOCOL_ADMIN", msg.sender);
        config.feedManager = vm.envOr("FEED_MANAGER", msg.sender);
        config.nodeManager = vm.envOr("NODE_MANAGER", msg.sender);
        config.priceManager = vm.envOr("PRICE_MANAGER", msg.sender);
        config.nodeRegistryOwner = vm.envOr("NODE_REGISTRY_OWNER", msg.sender);
        
        // USDC configuration
        config.usdcToken = vm.envOr("USDC_TOKEN", address(0));
        config.useExistingUSDC = vm.envOr("USE_EXISTING_USDC", false);
        
        return config;
    }

    function logDeployedAddresses(DeployedContracts memory contracts) internal view {
        console.log("\n=== Deployment Summary ===");
        console.log("AccessControlManager:", address(contracts.accessControlManager));
        console.log("NodeRegistry:", address(contracts.nodeRegistry)); 
        console.log("SubscriptionRegistry:", address(contracts.subscriptionRegistry));
        console.log("FeedRegistry:", address(contracts.feedRegistry));
        console.log("USDC Token:", address(contracts.usdcToken));
        console.log("\n=== Deployment Complete ===");
    }

    // Helper function to deploy to specific chains
    function deployToFuji() external returns (DeployedContracts memory) {
        vm.setEnv("CHAIN_ID", "43113");
        return this.run();
    }

    function deployToAvalanche() external returns (DeployedContracts memory) {
        vm.setEnv("CHAIN_ID", "43114");
        vm.setEnv("USE_EXISTING_USDC", "true");
        return this.run();
    }

    function deployToEthereum() external returns (DeployedContracts memory) {
        vm.setEnv("CHAIN_ID", "1");
        vm.setEnv("USE_EXISTING_USDC", "true");
        return this.run();
    }

    function deployToSepolia() external returns (DeployedContracts memory) {
        vm.setEnv("CHAIN_ID", "11155111");
        return this.run();
    }
} 