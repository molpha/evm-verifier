// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test, console2} from "forge-std/Test.sol";
import {MessageHashUtils} from "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

import {NodeRegistry} from "../src/NodeRegistry.sol";
import {Feed} from "../src/Feed.sol";
import {IFeed} from "../src/interfaces/IFeed.sol";
import {AccessControlManager} from "../src/AccessControlManager.sol";
import {INodeRegistry, INodeRegistryStructs} from "../src/interfaces/INodeRegistry.sol";
import {LibSecp256k1} from "../src/libs/LibSecp256k1.sol";
import {NodeGroupBitmapLib} from "../src/libs/NodeGroupBitmapLib.sol";
import {LibSchnorrTestSign} from "./libs/LibSchnorrTestSign.sol";

/// @title NodeRegistryPublishGasFullTest
///
/// Measures the TRUE on-chain cost to post one oracle round, including:
///
///   execution   — gasleft() delta around NodeRegistry.publish(), which captures the full
///                 call tree: NodeRegistry → Feed.getJobId() → Feed.getMinSignaturesThreshold()
///                 → AccessControlManager.verifyNodeRegistry() → Feed.publish() → event.
///
///   calldata    — computed in-test from abi.encodeCall(); priced at EIP-2028 rates
///                 (4 gas/zero byte, 16 gas/nonzero byte).
///
///   base tx     — 21,000 gas (fixed per EIP-2 for every L1 transaction).
///
///   total est.  — execution + calldata + base tx.
///
/// Uses the real Feed.sol (not DummyFeed) so the full call tree is representative.
///
/// Run:
///   forge test --match-path test/NodeRegistryPublishGasFull.t.sol -vv
///
/// @dev Do **not** pass `--gas-report` or `--isolate` when reading the printed `exec` / TOTAL
///      lines. Foundry runs each top-level external call as a separate tx in isolation mode
///      (which `--gas-report` turns on), so `gasleft()` deltas and the per-test `(gas: …)` no
///      longer match a normal, single-tx test — use a plain `forge test` for this benchmark, and
///      a separate run with `--gas-report` if you want the contract-level table only.
contract NodeRegistryPublishGasFullTest is Test {
    using MessageHashUtils for bytes32;
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.JacobianPoint;
    bytes32 internal constant POP_DOMAIN = keccak256("MOLPHA_NODE_REGISTRATION_V1");

    uint256 constant BASE_TX_GAS = 21_000;

    struct Call {
        INodeRegistryStructs.DataUpdate update;
        INodeRegistryStructs.SchnorrSignature schnorr;
        uint32[] participationMap;
    }

    // ─── Key helpers (mirrors NodeRegistryPublishGasTest) ─────────────────────

    function _secret(uint256 slot) internal pure returns (uint256) {
        return (uint256(keccak256(abi.encodePacked("MOLPHA_GAS_KEY", slot))) % (LibSecp256k1.Q() - 1)) + 1;
    }

    function _combinedKey(uint256[] memory signerSecrets) internal pure returns (uint256 sk) {
        uint256 Q = LibSecp256k1.Q();
        for (uint256 i; i < signerSecrets.length; ++i) sk = addmod(sk, signerSecrets[i], Q);
    }

    function _popSig(address registryAddr, bytes memory compressedPubKey, uint256 sk) internal view returns (bytes memory) {
        bytes32 digest = keccak256(abi.encodePacked(POP_DOMAIN, registryAddr, compressedPubKey)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _buildCall(
        NodeRegistry reg,
        address feed,
        bytes32 jobId,
        LibSecp256k1.Point[] memory allPubkeys,
        uint256[] memory allSecrets,
        uint256 nodeCount,
        uint256 threshold,
        bytes32 seed,
        uint32[] memory pm,
        uint32 round
    ) internal view returns (Call memory c) {
        uint256 groupSize = threshold + reg.redundancyBuffer();
        uint256 bitmap = NodeGroupBitmapLib.derive(seed, round, nodeCount, groupSize);

        uint256[] memory selected = new uint256[](groupSize);
        uint256 cnt;
        for (uint256 b; b < nodeCount && cnt < groupSize; ++b)
            if (bitmap & (uint256(1) << b) != 0) selected[cnt++] = b + 1;

        uint256 numSigners = threshold;
        uint256[] memory signerIdxs   = new uint256[](numSigners);
        LibSecp256k1.Point[] memory signerPts  = new LibSecp256k1.Point[](numSigners);
        uint256[] memory signerSecrets = new uint256[](numSigners);
        uint256 signerBits;
        for (uint256 i; i < numSigners; ++i) {
            uint256 regIdx = selected[i];
            signerIdxs[i] = regIdx;
            signerBits |= uint256(1) << (regIdx - 1);
            signerPts[i] = allPubkeys[regIdx - 1];
            signerSecrets[i] = allSecrets[regIdx - 1];
        }

        uint256 skEff = _combinedKey(signerSecrets);
        LibSecp256k1.Point memory aggKey = LibSecp256k1.mulAffine(LibSecp256k1.G(), skEff);

        bytes memory value = abi.encodePacked(uint256(round) * 1e18);
        uint64 ts = uint64(block.timestamp) + round;

        c.update = INodeRegistryStructs.DataUpdate({feed: feed, jobId: jobId, value: value, timestamp: ts, round: round});
        bytes32 message = keccak256(abi.encodePacked(c.update.jobId, c.update.value, c.update.timestamp, c.update.round)).toEthSignedMessageHash();
        (bytes32 sig, address cmt) = LibSchnorrTestSign.sign(aggKey, skEff, message, 0);
        c.schnorr =
            INodeRegistryStructs.SchnorrSignature({signature: sig, commitment: cmt, signersBitmap: bytes32(signerBits)});
        c.participationMap = pm;
    }

    function _advancePm(uint32[] memory pm, bytes32 signerBitmap) internal pure returns (uint32[] memory next) {
        next = new uint32[](pm.length);
        for (uint256 i; i < pm.length; ++i) next[i] = pm[i];
        uint256 sb = uint256(signerBitmap);
        for (uint256 pos; pos < pm.length; ++pos) {
            if (sb & (uint256(1) << pos) != 0) {
                next[pos]++;
            }
        }
    }

    // ─── Calldata cost calculator ─────────────────────────────────────────────

    /// @dev Prices calldata per EIP-2028: 4 gas per zero byte, 16 gas per nonzero byte.
    function _calldataCost(bytes memory data) internal pure returns (uint256 cost) {
        for (uint256 i; i < data.length; ++i)
            cost += (data[i] == 0) ? 4 : 16;
    }

    // ─── Setup ────────────────────────────────────────────────────────────────

    struct Scenario { uint256 nodeCount; uint256 threshold; }

    struct FullSetup {
        NodeRegistry reg;
        Call call1;
        Call call2;
        uint256 calldataCost1;
        uint256 calldataCost2;
    }

    function _setup(Scenario memory s) internal returns (FullSetup memory fs) {
        vm.pauseGasMetering();

        // Deploy contracts
        AccessControlManager acl = new AccessControlManager();
        acl.initialize(address(this));
        acl.grantRole(acl.NODE_REGISTRY(), address(this)); // for addNode / initializeJob

        fs.reg = new NodeRegistry();
        fs.reg.initialize(address(acl));

        // Add nodes
        LibSecp256k1.Point[] memory allPubkeys = new LibSecp256k1.Point[](s.nodeCount);
        uint256[] memory allSecrets = new uint256[](s.nodeCount);
        for (uint256 i; i < s.nodeCount; ++i) {
            allSecrets[i]  = _secret(i + 1);
            allPubkeys[i]  = LibSecp256k1.mulAffine(LibSecp256k1.G(), allSecrets[i]);
            bytes memory compressed = LibSecp256k1.compress(allPubkeys[i]);
            fs.reg.addNode(compressed, _popSig(address(fs.reg), compressed, allSecrets[i]));
        }

        // Deploy real Feed — nodeRegistry is set as an immutable, no ACL role needed.
        Feed feed = new Feed(
            IFeed.CreateFeedParams({
                feedType: IFeed.FeedType.PUBLIC,
                accessControlManager: address(acl),
                nodeRegistry: address(fs.reg),
                owner: address(this),
                frequency: 60,
                signaturesRequired: uint64(s.threshold),
                consumerPricePerSecondScaled: 0,
                jobId: bytes32(uint256(1)),
                dataSourceId: bytes32(uint256(2)),
                ipfsCID: "QmTest"
            })
        );

        (,, bytes32 jobId,) = feed.getFeedConfig();
        vm.warp(1_000_000);
        uint64 jobStartTime = uint64(block.timestamp);
        fs.reg.initializeJob(jobId, jobStartTime);

        uint32[] memory pm0 = new uint32[](s.nodeCount);
        bytes32 seed0 = fs.reg.getJobSeed(jobId);

        fs.call1 = _buildCall(fs.reg, address(feed), jobId, allPubkeys, allSecrets, s.nodeCount, s.threshold, seed0, pm0, 1);

        bytes32 seed1 = bytes32(
            uint256(keccak256(abi.encodePacked(seed0, fs.call1.update.value, fs.call1.update.timestamp)))
            & ~uint256(type(uint32).max)
        );
        uint32[] memory pm1 = _advancePm(pm0, fs.call1.schnorr.signersBitmap);
        fs.call2 = _buildCall(fs.reg, address(feed), jobId, allPubkeys, allSecrets, s.nodeCount, s.threshold, seed1, pm1, 2);

        // Warp past the latest answer timestamp so Feed's "Future timestamp" check passes.
        // Both calls have ts = block.timestamp + round (1 or 2), so warp beyond that.
        vm.warp(1_000_000 + 100);

        // Pre-compute calldata bytes for each call (for cost estimation)
        fs.calldataCost1 = _calldataCost(
            abi.encodeCall(INodeRegistry.publish, (fs.call1.update, fs.call1.schnorr))
        );
        fs.calldataCost2 = _calldataCost(
            abi.encodeCall(INodeRegistry.publish, (fs.call2.update, fs.call2.schnorr))
        );

        vm.resumeGasMetering();
    }

    // ─── Benchmark runner ─────────────────────────────────────────────────────

    function _runBench(Scenario memory s) internal {
        FullSetup memory fs = _setup(s);

        // ── Round 1: cold storage ──────────────────────────────────────────────
        uint256 gasBefore = gasleft();
        fs.reg.publish(fs.call1.update, fs.call1.schnorr);
        uint256 exec1 = gasBefore - gasleft();

        // ── Round 2: warm/dirty storage ───────────────────────────────────────
        gasBefore = gasleft();
        fs.reg.publish(fs.call2.update, fs.call2.schnorr);
        uint256 exec2 = gasBefore - gasleft();

        vm.pauseGasMetering();

        uint256 total1 = exec1  + fs.calldataCost1 + BASE_TX_GAS;
        uint256 total2 = exec2  + fs.calldataCost2 + BASE_TX_GAS;

        console2.log(string.concat(
            "nodes=", vm.toString(s.nodeCount),
            "  signers=", vm.toString(s.threshold)
        ));
        console2.log(string.concat(
            "  Round 1 (cold)  | exec: ", vm.toString(exec1),
            "  calldata: ", vm.toString(fs.calldataCost1),
            "  base: ", vm.toString(BASE_TX_GAS),
            "  TOTAL: ", vm.toString(total1)
        ));
        console2.log(string.concat(
            "  Round 2 (warm)  | exec: ", vm.toString(exec2),
            "  calldata: ", vm.toString(fs.calldataCost2),
            "  base: ", vm.toString(BASE_TX_GAS),
            "  TOTAL: ", vm.toString(total2)
        ));

        vm.resumeGasMetering();
    }

    // ─── Scenarios ────────────────────────────────────────────────────────────

    function test_full_nodes03_signers01() public { _runBench(Scenario({nodeCount:  3, threshold: 1})); }
    function test_full_nodes05_signers01() public { _runBench(Scenario({nodeCount:  5, threshold: 1})); }
    function test_full_nodes10_signers01() public { _runBench(Scenario({nodeCount: 10, threshold: 1})); }
    function test_full_nodes10_signers03() public { _runBench(Scenario({nodeCount: 10, threshold: 3})); }
    function test_full_nodes10_signers05() public { _runBench(Scenario({nodeCount: 10, threshold: 5})); }
    function test_full_nodes10_signers08() public { _runBench(Scenario({nodeCount: 10, threshold: 8})); }
    function test_full_nodes20_signers01() public { _runBench(Scenario({nodeCount: 20, threshold:  1})); }
    function test_full_nodes20_signers10() public { _runBench(Scenario({nodeCount: 20, threshold: 10})); }
    function test_full_nodes20_signers18() public { _runBench(Scenario({nodeCount: 20, threshold: 18})); }
    function test_full_nodes40_signers10() public { _runBench(Scenario({nodeCount: 40, threshold: 10})); }
    function test_full_nodes60_signers10() public { _runBench(Scenario({nodeCount: 60, threshold: 10})); }
    function test_full_nodes64_signers32() public { _runBench(Scenario({nodeCount: 64, threshold: 32})); }
    function test_full_nodes100_signers10() public { _runBench(Scenario({nodeCount: 100, threshold: 10})); }
}
