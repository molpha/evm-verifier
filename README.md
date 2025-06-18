# molpha-core-contracts

Smart contracts powering the Molpha decentralized oracle protocol.  
This repo contains the core logic for feed creation, aggregator verification, and subscription infrastructure.

---

## ⚙️ Contracts Overview

### `IFeed.sol`
- Stores the latest feed value
- Value is returned as `bytes`, with optional metadata (timestamp, update count)
- Only the verified Aggregator contract can call `pushUpdate()`

### `IFeedRegistry.sol`
- Allows feed creators to register feeds
- Tracks metadata hashes (e.g., IPFS, Arweave)
- Returns on-chain feed addresses

### `IAggregator.sol`
- Registers and manages oracle nodes
- Verifies aggregated Schnorr signatures from nodes
- Submits updates to `IFeed` contracts
- Verifies bitmap participation and prevents replay attacks

### `ISubscriptionRegistry.sol`
- Manages consumer subscriptions
- Accepts USDC for feed access
- Tracks expiration times for each subscriber

---

## 🧱 Architecture Summary

```text
              [ Off-chain Aggregator Entity ]
                        |
     Collects node signatures (via bitmap, schnorr, etc.)
                        |
                    [ On-chain ]
                          |
            +----------------------------+
            | Aggregator Contract        |
            | - Manages registered nodes |
            | - Verifies bitmap + sigs   |
            | - Handles batching         |
            +-------------+--------------+
                          |
                          v
                    [ Feed Contract ]
                  - Stores feed data
                  - Accessed by consumers
```

---

## 🔒 Security Considerations

- Nodes and aggregators must stake USDC to participate
- Signature verification ensures data integrity
- Feeds are permissionlessly readable but only updated by trusted aggregators
- Replay protection via update counter and timestamp validation

---

## 🛠 Setup

This repository uses [Foundry](https://book.getfoundry.sh/) for Solidity development.

```bash
forge install
forge build
forge test
```

---

## 📄 License

MIT or Business Source License depending on module. See individual file headers.

---

## 👥 Authors

Maintained by the Molpha core protocol team.
