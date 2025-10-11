# Contract Update Scripts

This directory contains scripts for updating deployed contracts in the Molpha Core Contracts system.

## Available Scripts

### 1. UpdateDataSourceRegistry.s.sol
A simple script to update only the DataSourceRegistry contract.

**Usage:**
```bash
# Set environment variables
export PRIVATE_KEY=your_private_key
export PROXY_ADMIN=0x...
export DATA_SOURCE_REGISTRY_PROXY=0x...

# Run the script
forge script script/UpdateDataSourceRegistry.s.sol:UpdateDataSourceRegistry \
    --rpc-url <your_rpc_url> \
    --broadcast \
    --verify
```

### 2. UpdateContracts.s.sol
A comprehensive script to update multiple contracts at once.

**Usage:**
```bash
# Set environment variables
export PRIVATE_KEY=your_private_key
export PROXY_ADMIN=0x...
export USDC=0x...
export DATA_SOURCE_REGISTRY_PROXY=0x...  # Optional
export FEED_REGISTRY_PROXY=0x...         # Optional
export SUBSCRIPTION_REGISTRY_PROXY=0x... # Optional
export NODE_REGISTRY_PROXY=0x...         # Optional
export TREASURY_PROXY=0x...              # Optional
export PRICING_HELPER_PROXY=0x...        # Optional
export ACCESS_CONTROL_MANAGER_PROXY=0x... # Optional

# Run the script
forge script script/UpdateContracts.s.sol:UpdateContracts \
    --rpc-url <your_rpc_url> \
    --broadcast \
    --verify
```

## Shell Scripts

### 1. update-datasource-registry.sh
Automated script to update DataSourceRegistry using address files.

**Usage:**
```bash
./update-datasource-registry.sh <network> <rpc_url>
```

**Example:**
```bash
./update-datasource-registry.sh fuji https://avax-fuji.g.alchemy.com/v2/YOUR_API_KEY
```

### 2. update-contracts.sh
Automated script to update multiple contracts using address files.

**Usage:**
```bash
./update-contracts.sh <network> <rpc_url> [contract1,contract2,...]
```

**Examples:**
```bash
# Update only DataSourceRegistry (default)
./update-contracts.sh fuji https://avax-fuji.g.alchemy.com/v2/YOUR_API_KEY

# Update multiple contracts
./update-contracts.sh fuji https://avax-fuji.g.alchemy.com/v2/YOUR_API_KEY DataSourceRegistry,FeedRegistry

# Update all contracts
./update-contracts.sh fuji https://avax-fuji.g.alchemy.com/v2/YOUR_API_KEY DataSourceRegistry,FeedRegistry,SubscriptionRegistry,NodeRegistry,Treasury,PricingHelper,AccessControlManager
```

## Available Contracts for Update

- `DataSourceRegistry` - Data source registration and management
- `FeedRegistry` - Feed registration and management
- `SubscriptionRegistry` - Subscription management
- `NodeRegistry` - Node registration and management
- `Treasury` - Treasury management
- `PricingHelper` - Pricing calculations
- `AccessControlManager` - Access control management

## Prerequisites

1. **Environment Variables:**
   - `PRIVATE_KEY` - Your deployment private key
   - `PROXY_ADMIN` - Address of the ProxyAdmin contract
   - `USDC` - Address of the USDC token (for Treasury updates)

2. **Address Files:**
   - The shell scripts automatically read from address files in the format `addresses-*<network>*.json`
   - These files should contain the deployed contract addresses

3. **Network Configuration:**
   - Ensure your RPC URL is correct for the target network
   - Verify that the address file corresponds to the correct network

## Important Notes

1. **Proxy Pattern:** All contracts use the TransparentUpgradeableProxy pattern, so the proxy addresses remain the same while only the implementation is updated.

2. **Verification:** The scripts include `--verify` flag to verify contracts on block explorers.

3. **Gas Costs:** Updating contracts requires gas fees. Ensure your account has sufficient funds.

4. **Testing:** Always test updates on testnets before deploying to mainnet.

5. **Backup:** The scripts create new address files with the updated implementation addresses.

## Error Handling

- The scripts will skip contracts if their proxy addresses are not found in the address file
- Invalid contract names will be ignored with a warning message
- Missing environment variables will cause the script to fail with clear error messages

## Security Considerations

1. **Access Control:** Ensure only authorized accounts can execute updates
2. **Verification:** Always verify the new implementation addresses after deployment
3. **Testing:** Test thoroughly on testnets before mainnet deployment
4. **Documentation:** Keep track of all updates and their purposes 