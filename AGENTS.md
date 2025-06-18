# AGENTS.md - Molpha Core Contracts

## 🎯 Project Overview

**Molpha Core Contracts** is a decentralized oracle protocol built on Ethereum using Solidity. The project implements a comprehensive infrastructure for:

- **Data Feeds**: On-chain storage and retrieval of oracle data
- **Node Aggregation**: Verification of off-chain oracle nodes using Schnorr signatures
- **Subscription Management**: USDC-based access control for feed consumers
- **Access Control**: Role-based permissions for protocol management

---

## 🏗️ Architecture Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                     Molpha Oracle Protocol                     │
├─────────────────────────────────────────────────────────────────┤
│  Off-chain: Oracle Nodes → Aggregator Entity → Schnorr Sigs   │
├─────────────────────────────────────────────────────────────────┤
│  On-chain: NodeAggregator → Feed Contracts → Consumer Access   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📁 Project Structure

```
molpha-core-contracts/
├── foundry.toml                 # Foundry configuration
├── src/                         # Smart contracts source
│   ├── Feed.sol                 # Core feed contract (data storage)
│   ├── FeedsRegistry.sol        # Feed factory and management
│   ├── NodeAggregator.sol       # Oracle node verification
│   ├── SubscriptionRegistry.sol # Consumer subscription management
│   ├── interfaces/              # Contract interfaces
│   │   ├── IFeed.sol
│   │   ├── IFeedsRegistry.sol
│   │   ├── INodesAggregator.sol
│   │   ├── ISubscriptionsRegistry.sol
│   │   ├── IAccessControlManager.sol
│   │   ├── IFeedsFactory.sol
│   │   └── ICommonErrors.sol
│   └── libs/                    # Utility libraries
│       ├── ERC165Checker.sol    # Interface verification
│       ├── LibSchnorr.sol       # Schnorr signature verification
│       ├── LibSecp256k1.sol     # Elliptic curve operations
│       └── SchnorrSetVerifierLib.sol
├── test/                        # Test files (currently empty)
├── script/                      # Deployment scripts
├── references/                  # Reference implementations
└── lib/                         # Dependencies (Foundry modules)
```

---

## 🔧 Technology Stack

- **Framework**: Foundry (Solidity development)
- **Language**: Solidity ^0.8.29
- **Dependencies**: OpenZeppelin Contracts
- **Cryptography**: Schnorr signatures, secp256k1 curve
- **Standards**: ERC165 for interface detection

---

## 🚀 Quick Setup Commands

```bash
# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test

# Format code
forge fmt

# Deploy to local testnet
anvil  # Terminal 1
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --private-key 0x... --broadcast  # Terminal 2
```

---

## 🎯 Core Contracts Deep Dive

### 1. **Feed.sol** - The Data Storage Layer
- **Purpose**: Stores oracle data with timestamp validation
- **Key Features**:
  - Answer history with `Answer[]` array
  - Subscription-based access control
  - Schnorr signature verification for updates
  - ERC165 interface support

**Key Functions**:
```solidity
function publishAnswer(Answer calldata answer, INodesAggregator.SchnorrSignature calldata schnorrData) external
function getLatest() external view returns (bytes memory value, uint256 timestamp)
function getEntry(uint256 index) external view returns (bytes memory value, uint256 timestamp)
```

### 2. **FeedsRegistry.sol** - Feed Management
- **Purpose**: Factory pattern for creating and managing feeds
- **Key Features**:
  - Feed creation with metadata hashes
  - Subscription price management
  - Access control integration
  - Feed validation and tracking

**Key Functions**:
```solidity
function createFeed(bytes32 metadataHash, uint256 rewardForAnswer, uint128 subscriptionPrice, uint256 minSignaturesThreshold) external returns (address feed)
function setSubscriptionPrice(address feed, uint128 price) external
function isFeed(address feed) external view returns (bool)
```

### 3. **NodeAggregator.sol** - Oracle Node Verification
- **Purpose**: Manages oracle nodes and verifies their collective signatures
- **Key Features**:
  - Node registration and management
  - Schnorr signature aggregation
  - Bitmap-based participation tracking
  - Threshold signature verification

### 4. **SubscriptionRegistry.sol** - Access Control
- **Purpose**: Manages consumer subscriptions and payments
- **Key Features**:
  - USDC-based subscription payments
  - Time-based access expiration
  - Feed-specific subscription tracking

---

## 🧠 AI Assistant Context & Prompts

### **Context for ChatGPT/Codex**

When working with this codebase, provide the AI with this context:

```
This is a Solana-style oracle protocol built on Ethereum. Key concepts:

1. FEEDS: Store oracle data with timestamp validation
2. NODES: Off-chain oracle providers that sign data
3. AGGREGATION: Schnorr signature verification for data integrity
4. SUBSCRIPTIONS: USDC-based access control for consumers
5. REGISTRY: Factory pattern for feed creation and management

The codebase uses:
- Foundry for development and testing
- OpenZeppelin for standard implementations
- Custom cryptographic libraries for Schnorr signatures
- ERC165 for interface detection
- Role-based access control patterns
```

### **Recommended AI Prompts for Productivity**

#### **Code Review & Analysis**
```
"Review this Solidity contract for security vulnerabilities, gas optimizations, and best practices. Focus on:
1. Reentrancy protection
2. Access control validation
3. Input validation and edge cases
4. Gas optimization opportunities
5. Integration with existing Molpha protocol patterns"
```

#### **Testing Strategy**
```
"Generate comprehensive Foundry tests for this contract including:
1. Happy path scenarios
2. Edge cases and error conditions
3. Access control validation
4. Gas usage benchmarks
5. Integration tests with other protocol contracts"
```

#### **Documentation Generation**
```
"Generate comprehensive NatSpec documentation for this contract following Ethereum documentation standards. Include:
1. Contract purpose and architecture
2. Function descriptions with parameters and return values
3. Event documentation
4. Error conditions and custom errors
5. Usage examples and integration patterns"
```

#### **Deployment & Scripts**
```
"Create Foundry deployment scripts for this contract that:
1. Handle proper initialization order
2. Verify contract interfaces
3. Set up proper access controls
4. Include deployment verification
5. Generate deployment documentation"
```

---

## 🔍 Common Development Patterns

### **Interface Validation Pattern**
```solidity
// Used throughout the codebase
address(contract).shouldSupport(type(IInterface).interfaceId);
```

### **Access Control Pattern**
```solidity
modifier onlyFeedsManager() {
    _accessControlManager.verifyFeedsManager(msg.sender);
    _;
}
```

### **Subscription Validation Pattern**
```solidity
modifier onlyValidConsumer() {
    if (!_subscriptionsRegistry.isSubscribed(msg.sender, address(this)) && tx.origin != msg.sender) {
        revert NotSubscribed(msg.sender);
    }
    _;
}
```

---

## 🧪 Testing Guidelines

### **Test Structure**
- Use Foundry's testing framework
- Follow `test_MethodName_Condition_ExpectedResult` naming
- Group tests by contract in separate files
- Use fuzzing for input validation

### **Key Test Scenarios**
1. **Feed Operations**: Data publishing, retrieval, subscription validation
2. **Access Control**: Role-based permissions, unauthorized access attempts
3. **Cryptography**: Schnorr signature verification, invalid signature handling
4. **Economic**: Subscription payments, reward distribution, fee calculation
5. **Integration**: Cross-contract interactions, factory patterns

---

## 🛡️ Security Considerations

### **Critical Security Areas**
1. **Signature Verification**: Schnorr signature validation must be bulletproof
2. **Timestamp Validation**: Prevent replay attacks and future timestamps
3. **Access Control**: Ensure proper role verification throughout
4. **Subscription Logic**: Validate payment and expiration logic
5. **Upgradability**: Consider proxy patterns for future upgrades

### **Common Vulnerabilities to Check**
- Reentrancy in state-changing functions
- Integer overflow/underflow (though Solidity 0.8+ has built-in protection)
- Improper access control validation
- Front-running in fee/subscription updates
- Oracle manipulation through invalid signatures

---

## 📚 Useful Resources

### **Development**
- [Foundry Book](https://book.getfoundry.sh/)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)
- [Solidity Documentation](https://docs.soliditylang.org/)

### **Cryptography**
- [Schnorr Signatures](https://en.wikipedia.org/wiki/Schnorr_signature)
- [secp256k1 Curve](https://en.bitcoin.it/wiki/Secp256k1)

### **Oracle Patterns**
- [Chainlink Architecture](https://docs.chain.link/architecture-overview)
- [Oracle Problem](https://blog.chain.link/what-is-the-blockchain-oracle-problem/)

---

## 🎯 Productivity Tips

### **AI-Assisted Development Workflow**
1. **Start with Interface**: Ask AI to help design interfaces first
2. **Generate Tests**: Create comprehensive tests before implementation
3. **Security Review**: Regular security audits with AI assistance
4. **Documentation**: Auto-generate and maintain documentation
5. **Gas Optimization**: Regular gas usage analysis and optimization

### **Code Quality Checklist**
- [ ] All functions have proper NatSpec documentation
- [ ] Access control is properly implemented
- [ ] Input validation is comprehensive
- [ ] Events are emitted for state changes
- [ ] Error messages are descriptive
- [ ] Gas usage is optimized
- [ ] Integration tests pass
- [ ] Security review completed

---

## 🔄 Development Lifecycle

### **Feature Development**
1. **Design**: Interface definition and architecture planning
2. **Implementation**: Contract development with AI assistance
3. **Testing**: Comprehensive test suite creation
4. **Review**: Security and code quality review
5. **Documentation**: Update documentation and comments
6. **Deployment**: Staging and production deployment

### **Maintenance**
- Regular security audits
- Gas optimization reviews
- Integration testing with protocol updates
- Documentation updates
- Dependency management

---

*This document is designed to maximize productivity when working with AI assistants like ChatGPT Codex on the Molpha Oracle Protocol. Keep it updated as the project evolves.* 