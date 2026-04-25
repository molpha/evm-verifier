// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test, console2} from "forge-std/Test.sol";
import {MessageHashUtils} from "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

import {NodeRegistry} from "../src/NodeRegistry.sol";
import {AccessControlManager} from "../src/AccessControlManager.sol";
import {INodeRegistry, INodeRegistryStructs} from "../src/interfaces/INodeRegistry.sol";
import {LibSecp256k1} from "../src/libs/LibSecp256k1.sol";
import {NodeGroupBitmapLib} from "../src/libs/NodeGroupBitmapLib.sol";
import {LibSchnorrTestSign} from "./libs/LibSchnorrTestSign.sol";
import {DummyFeed} from "./mocks/DummyFeed.sol";

/// @title NodeRegistryPublishGasTest
///
/// Measures ONLY the gas consumed inside NodeRegistry.publish().
///
/// Two calls are measured per scenario:
///   "first"  — storage slots are cold (written by setup in a prior call frame).
///               SLOADs cost 2100 gas; nonzero→nonzero SSTOREs cost 5000 gas.
///   "second" — storage slots are warm/dirty from the first publish().
///               SLOADs cost 100 gas; dirty SSTOREs cost 100–2900 gas.
///
/// All setup code runs inside vm.pauseGasMetering() blocks so it is completely
/// excluded from Forge's gas accounting. Gas is captured via gasleft() around
/// the bare publish() call.
///
/// Run:
///   forge test --match-path test/NodeRegistryPublishGas.t.sol -vv
///   forge test --match-path test/NodeRegistryPublishGas.t.sol --gas-report
contract NodeRegistryPublishGasTest is Test {
    using MessageHashUtils for bytes32;
    using LibSecp256k1 for LibSecp256k1.Point;
    using LibSecp256k1 for LibSecp256k1.JacobianPoint;
    bytes32 internal constant POP_DOMAIN = keccak256("MOLPHA_NODE_REGISTRATION_V1");

    // ─── Pre-signed call bundle ───────────────────────────────────────────────

    /// @dev Everything publish() needs, pre-computed off-chain so signing cost
    ///      is never included in the gas measurement.
    struct Call {
        INodeRegistryStructs.DataUpdate update;
        INodeRegistryStructs.SchnorrSignature schnorr;
        uint32[] participationMap; // matches current registry state before this call
    }

    // ─── Helpers: keys ────────────────────────────────────────────────────────

    function _secret(uint256 slot) internal pure returns (uint256) {
        return (uint256(keccak256(abi.encodePacked("MOLPHA_GAS_KEY", slot))) % (LibSecp256k1.Q() - 1)) + 1;
    }

    // ─── Helpers: bitmap (NodeGroupBitmapLib.derive) ─────────────────────────

    // ─── Helpers: plain-sum combined private key ──────────────────────────────
    function _combinedKey(uint256[] memory signerSecrets) internal pure returns (uint256 sk) {
        uint256 Q = LibSecp256k1.Q();
        for (uint256 i; i < signerSecrets.length; ++i) {
            sk = addmod(sk, signerSecrets[i], Q);
        }
    }

    function _popSig(address registryAddr, bytes memory compressedPubKey, uint256 sk) internal view returns (bytes memory) {
        bytes32 digest = keccak256(abi.encodePacked(POP_DOMAIN, registryAddr, compressedPubKey)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sk, digest);
        return abi.encodePacked(r, s, v);
    }

    // ─── Helpers: pre-compute a signed Call bundle ────────────────────────────

    /// @dev Builds a fully-signed Call for the given round without touching the registry.
    ///      `seed` is the prevSeed the contract will use for bitmap derivation this round
    ///      (initial seed for round 1; keccak256(prevSeed||value||ts) for subsequent rounds).
    ///      `pm` must be the participation map that the registry currently expects.
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
        require(groupSize <= nodeCount, "groupSize > nodeCount");

        uint256 bitmap = NodeGroupBitmapLib.derive(seed, round, nodeCount, groupSize);

        // Collect selected 1-based node indices (ascending, low bit first).
        uint256[] memory selected = new uint256[](groupSize);
        uint256 cnt;
        for (uint256 b; b < nodeCount && cnt < groupSize; ++b) {
            if (bitmap & (uint256(1) << b) != 0) selected[cnt++] = b + 1;
        }

        // Use the first `threshold` selected nodes as signers.
        uint256 numSigners = threshold;
        uint256[] memory signerIdxs = new uint256[](numSigners);
        LibSecp256k1.Point[] memory signerPts = new LibSecp256k1.Point[](numSigners);
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

        c.update =
            INodeRegistryStructs.DataUpdate({feed: feed, jobId: jobId, value: value, timestamp: ts, round: round});

        bytes32 message = keccak256(
            abi.encodePacked(c.update.jobId, c.update.value, c.update.timestamp, c.update.round)
        ).toEthSignedMessageHash();
        (bytes32 sig, address cmt) = LibSchnorrTestSign.sign(aggKey, skEff, message, 0);

        c.schnorr =
            INodeRegistryStructs.SchnorrSignature({signature: sig, commitment: cmt, signersBitmap: bytes32(signerBits)});
        c.participationMap = pm;
    }

    /// @dev Returns the participation map that results after a publish call with the given signers.
    function _advancePm(uint32[] memory pm, bytes32 signerBitmap) internal pure returns (uint32[] memory next) {
        next = new uint32[](pm.length);
        for (uint256 i; i < pm.length; ++i) {
            next[i] = pm[i];
        }
        uint256 sb = uint256(signerBitmap);
        for (uint256 pos; pos < pm.length; ++pos) {
            if (sb & (uint256(1) << pos) != 0) {
                next[pos]++;
            }
        }
    }

    // ─── Core benchmark ───────────────────────────────────────────────────────

    struct Scenario {
        uint256 nodeCount;
        uint256 threshold; // minSignaturesThreshold (= numSigners used)
    }

    /// @dev Deploys a fresh registry, adds nodes, initialises a job, and returns two
    ///      pre-signed Call bundles: one for round 1 (first publish) and one for round 2
    ///      (second publish after storage has been dirtied by round 1).
    ///
    ///      Every line here runs inside vm.pauseGasMetering() — none of this appears
    ///      in Forge's gas accounting.
    function _setupAndPreSign(Scenario memory s)
        internal
        returns (NodeRegistry reg, Call memory call1, Call memory call2)
    {
        vm.pauseGasMetering();

        reg = new NodeRegistry();
        AccessControlManager acl = new AccessControlManager();
        acl.initialize(address(this));
        acl.grantRole(acl.NODE_REGISTRY(), address(this));
        reg.initialize(address(acl));

        LibSecp256k1.Point[] memory allPubkeys = new LibSecp256k1.Point[](s.nodeCount);
        uint256[] memory allSecrets = new uint256[](s.nodeCount);
        for (uint256 i; i < s.nodeCount; ++i) {
            allSecrets[i] = _secret(i + 1);
            allPubkeys[i] = LibSecp256k1.mulAffine(LibSecp256k1.G(), allSecrets[i]);
            bytes memory compressed = LibSecp256k1.compress(allPubkeys[i]);
            reg.addNode(compressed, _popSig(address(reg), compressed, allSecrets[i]));
        }

        DummyFeed feed = new DummyFeed();
        feed.setMinSignaturesThreshold(s.threshold);
        (,, bytes32 jobId,) = feed.getFeedConfig();
        vm.warp(1_000_000);
        reg.initializeJob(jobId, uint64(block.timestamp));

        uint32[] memory pm0 = new uint32[](s.nodeCount);

        bytes32 seed0 = reg.getJobSeed(jobId); // prevSeed for round 1

        call1 = _buildCall(reg, address(feed), jobId, allPubkeys, allSecrets, s.nodeCount, s.threshold, seed0, pm0, 1);

        // The seed committed by round 1: keccak256(prevSeed || value || timestamp), then
        // truncated to 224 bits (low 32 bits zeroed) — matches _packJobState in NodeRegistry.
        bytes32 seed1 = bytes32(
            uint256(keccak256(abi.encodePacked(seed0, call1.update.value, call1.update.timestamp)))
            & ~uint256(type(uint32).max)
        );
        uint32[] memory pm1 = _advancePm(pm0, call1.schnorr.signersBitmap);
        call2 = _buildCall(reg, address(feed), jobId, allPubkeys, allSecrets, s.nodeCount, s.threshold, seed1, pm1, 2);

        vm.resumeGasMetering();
    }

    /// @dev Runs two publish() calls and prints gas for each.
    ///      Only the publish() call itself is between the gasleft() probes;
    ///      everything else (pre-sign, post-update) is paused.
    function _runBench(Scenario memory s) internal {
        (NodeRegistry reg, Call memory c1, Call memory c2) = _setupAndPreSign(s);

        // ── First publish (cold storage: slots last written in a prior call frame) ──
        uint256 gasBefore = gasleft();
        reg.publish(c1.update, c1.schnorr);
        uint256 firstGas = gasBefore - gasleft();

        // ── Second publish (warm/dirty storage: slots touched by the first publish) ──
        gasBefore = gasleft();
        reg.publish(c2.update, c2.schnorr);
        uint256 secondGas = gasBefore - gasleft();

        vm.pauseGasMetering();
        console2.log(
            string.concat(
                "nodes=",
                vm.toString(s.nodeCount),
                "  signers=",
                vm.toString(s.threshold),
                "  |  first (cold slots): ",
                vm.toString(firstGas),
                "  |  second (warm slots): ",
                vm.toString(secondGas),
                "  |  delta: ",
                vm.toString(firstGas - secondGas)
            )
        );
        vm.resumeGasMetering();
    }

    // ─── Group 1: Varying node count, 1 signer ────────────────────────────────
    // groupSize = 1 + redundancyBuffer(2) = 3 in all cases.
    // Isolates the cost of reading/writing larger SSTORE2 pubkey blobs and
    // participation maps as the node count grows.

    function test_gas_nodes03_signers01() public {
        _runBench(Scenario({nodeCount: 3, threshold: 1}));
    }

    function test_gas_nodes05_signers01() public {
        _runBench(Scenario({nodeCount: 5, threshold: 1}));
    }

    function test_gas_nodes10_signers01() public {
        _runBench(Scenario({nodeCount: 10, threshold: 1}));
    }

    function test_gas_nodes20_signers01() public {
        _runBench(Scenario({nodeCount: 20, threshold: 1}));
    }

    // ─── Group 2: Varying signer count, 10 nodes ─────────────────────────────
    // groupSize = threshold + 2.  Requires groupSize ≤ nodeCount=10.
    // Isolates the cost of aggregating more EC points in _verifySignature.

    function test_gas_nodes10_signers03() public {
        _runBench(Scenario({nodeCount: 10, threshold: 3}));
    }

    function test_gas_nodes10_signers05() public {
        _runBench(Scenario({nodeCount: 10, threshold: 5}));
    }

    function test_gas_nodes10_signers08() public {
        _runBench(Scenario({nodeCount: 10, threshold: 8}));
    }

    // ─── Group 3: Large node set, large coalition ─────────────────────────────

    function test_gas_nodes20_signers10() public {
        _runBench(Scenario({nodeCount: 20, threshold: 10}));
    }

    function test_gas_nodes20_signers18() public {
        _runBench(Scenario({nodeCount: 20, threshold: 18}));
    }
}
