// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test, console2} from "forge-std/Test.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";
import {MessageHashUtils} from "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

import {NodeRegistry} from "../src/NodeRegistry.sol";
import {AccessControlManager} from "../src/AccessControlManager.sol";
import {INodeRegistry, INodeRegistryStructs} from "../src/interfaces/INodeRegistry.sol";
import {LibSecp256k1} from "../src/libs/LibSecp256k1.sol";
import {LibMuSig2KeyAgg} from "../src/libs/LibMuSig2KeyAgg.sol";
import {LibSchnorr} from "../src/libs/LibSchnorr.sol";
import {LibSchnorrTestSign} from "./libs/LibSchnorrTestSign.sol";
import {DummyFeed} from "./mocks/DummyFeed.sol";

/// @title NodeRegistryPublishGasDrilldown
/// @notice Micro-benchmarks for each phase inside NodeRegistry.publish().
///
/// Run:
///   forge test --match-path test/NodeRegistryPublishGasDrilldown.t.sol -vv
contract NodeRegistryPublishGasDrilldown is Test {
    using MessageHashUtils for bytes32;
    using LibSecp256k1 for LibSecp256k1.Point;

    function _secret(uint256 slot) internal pure returns (uint256) {
        return (uint256(keccak256(abi.encodePacked("MOLPHA_GAS_KEY", slot))) % (LibSecp256k1.Q() - 1)) + 1;
    }

    function _measure(string memory label, uint256 gas) internal view {
        console2.log(string.concat("  ", label, ": ", vm.toString(gas)));
    }

    // ─── Phase 1: SSTORE2 read + abi.decode of pubkeys blob ──────────────────

    function test_phase_sstore2_read() public {
        vm.pauseGasMetering();

        // Build blobs of varying sizes and write them
        uint256[] memory nodeCounts = new uint256[](4);
        nodeCounts[0] = 3; nodeCounts[1] = 5; nodeCounts[2] = 10; nodeCounts[3] = 20;

        console2.log("=== SSTORE2.read + abi.decode(Point[]) ===");
        for (uint256 ci; ci < nodeCounts.length; ++ci) {
            uint256 n = nodeCounts[ci];
            // Simulate the keys blob stored in NodeRegistry.pointer:
            // keys[0] is aggregate key, keys[1..n] are node public keys.
            LibSecp256k1.Point[] memory keys = new LibSecp256k1.Point[](n + 1);
            for (uint256 i = 1; i <= n; ++i) {
                keys[i] = LibSecp256k1.mulAffine(LibSecp256k1.G(), _secret(i));
            }
            keys[0] = LibSecp256k1.ZERO_POINT();

            // NodeRegistry stores: abi.encode(Point[])
            bytes memory encoded = abi.encode(keys);
            address ptr = SSTORE2.write(encoded);

            vm.resumeGasMetering();
            uint256 g = gasleft();
            bytes memory raw = SSTORE2.read(ptr);
            LibSecp256k1.Point[] memory decoded = abi.decode(raw, (LibSecp256k1.Point[]));
            g = g - gasleft();
            vm.pauseGasMetering();

            _measure(string.concat("nodes=", vm.toString(n), " blob=", vm.toString(encoded.length), "B"), g);
            (decoded); // silence unused warning
        }
    }

    // ─── Phase 2: mulAffine (EC scalar multiplication) ───────────────────────

    function test_phase_mulAffine() public {
        vm.pauseGasMetering();
        console2.log("=== LibSecp256k1.mulAffine (one EC scalar mult) ===");

        LibSecp256k1.Point memory G = LibSecp256k1.G();
        uint256[] memory scalars = new uint256[](3);
        scalars[0] = _secret(1);
        scalars[1] = _secret(2);
        scalars[2] = _secret(3);

        for (uint256 i; i < scalars.length; ++i) {
            vm.resumeGasMetering();
            uint256 g = gasleft();
            LibSecp256k1.Point memory result = LibSecp256k1.mulAffine(G, scalars[i]);
            g = g - gasleft();
            vm.pauseGasMetering();
            _measure(string.concat("scalar_", vm.toString(i + 1)), g);
            (result);
        }
    }

    // ─── Phase 3: MuSig2 key aggregation (N mulAffine calls) ─────────────────

    function test_phase_aggregateKeys() public {
        vm.pauseGasMetering();
        console2.log("=== LibMuSig2KeyAgg.aggregateKeys(N signers) ===");

        // Pre-compute signer points
        LibSecp256k1.Point[] memory allPts = new LibSecp256k1.Point[](20);
        for (uint256 i; i < 20; ++i) {
            allPts[i] = LibSecp256k1.mulAffine(LibSecp256k1.G(), _secret(i + 1));
        }

        uint256[] memory sizes = new uint256[](6);
        sizes[0] = 1; sizes[1] = 2; sizes[2] = 3; sizes[3] = 5; sizes[4] = 8; sizes[5] = 10;

        for (uint256 si; si < sizes.length; ++si) {
            uint256 n = sizes[si];
            LibSecp256k1.Point[] memory pts = new LibSecp256k1.Point[](n);
            for (uint256 i; i < n; ++i) pts[i] = allPts[i];

            vm.resumeGasMetering();
            uint256 g = gasleft();
            LibSecp256k1.Point memory agg = LibMuSig2KeyAgg.aggregateKeys(pts);
            g = g - gasleft();
            vm.pauseGasMetering();

            _measure(string.concat("signers=", vm.toString(n)), g);
            (agg);
        }
    }

    // ─── Phase 4: Schnorr verification (ecrecover path) ──────────────────────

    function test_phase_schnorrVerify() public {
        vm.pauseGasMetering();
        console2.log("=== LibSchnorr.verifySignature (ecrecover) ===");

        uint256 sk = _secret(1);
        LibSecp256k1.Point memory pk = LibSecp256k1.mulAffine(LibSecp256k1.G(), sk);
        bytes32 message = keccak256("test message").toEthSignedMessageHash();
        (bytes32 sig, address cmt) = LibSchnorrTestSign.sign(pk, sk, message, 0);

        vm.resumeGasMetering();
        uint256 g = gasleft();
        bool valid = LibSchnorr.verifySignature(pk, message, sig, cmt);
        g = g - gasleft();
        vm.pauseGasMetering();

        _measure("single key verify", g);
        assertTrue(valid);
    }

    // ─── Phase 5: _deriveBitmap ───────────────────────────────────────────────

    function test_phase_deriveBitmap() public {
        vm.pauseGasMetering();
        console2.log("=== _deriveBitmap (selection loop) ===");

        bytes32 seed = keccak256("test seed");
        uint256[] memory nodeCounts = new uint256[](3);
        nodeCounts[0] = 5; nodeCounts[1] = 10; nodeCounts[2] = 20;

        for (uint256 ci; ci < nodeCounts.length; ++ci) {
            uint256 nodeCount = nodeCounts[ci];
            uint256 groupSize = 3; // threshold=1 + buffer=2

            vm.resumeGasMetering();
            uint256 g = gasleft();
            uint256 bitmap = _deriveBitmap(seed, 1, nodeCount, groupSize);
            g = g - gasleft();
            vm.pauseGasMetering();

            _measure(string.concat("nodes=", vm.toString(nodeCount), " groupSize=3"), g);
            (bitmap);
        }
    }

    function _deriveBitmap(bytes32 seed, uint32 round, uint256 nodeCount, uint256 groupSize)
        internal pure returns (uint256 bitmap)
    {
        uint256 selected; uint256 attempt;
        while (selected < groupSize) {
            uint256 pos = uint256(keccak256(abi.encodePacked(seed, uint256(round), attempt))) % nodeCount;
            uint256 bit = uint256(1) << pos;
            if (bitmap & bit == 0) { bitmap |= bit; ++selected; }
            ++attempt;
        }
    }

    // ─── Phase 6: SSTORE2.write (job state update) ───────────────────────────

    function test_phase_sstore2_write() public {
        vm.pauseGasMetering();
        console2.log("=== SSTORE2.write (JobState per round) ===");

        // JobState = {bytes32 seed, uint32 round} → abi.encoded = 64 bytes
        bytes32 seed = keccak256("seed");
        for (uint32 round = 1; round <= 3; ++round) {
            bytes memory data = abi.encode(seed, round);
            vm.resumeGasMetering();
            uint256 g = gasleft();
            address ptr = SSTORE2.write(data);
            g = g - gasleft();
            vm.pauseGasMetering();
            _measure(string.concat("round=", vm.toString(round), " size=", vm.toString(data.length), "B"), g);
            (ptr);
        }
    }

    // ─── Phase 7: participation map hash update ───────────────────────────────

    function test_phase_participationMap() public {
        vm.pauseGasMetering();
        console2.log("=== keccak256(abi.encode(participationMap)) ===");

        uint256[] memory nodeCounts = new uint256[](4);
        nodeCounts[0] = 3; nodeCounts[1] = 5; nodeCounts[2] = 10; nodeCounts[3] = 20;

        for (uint256 ci; ci < nodeCounts.length; ++ci) {
            uint256 n = nodeCounts[ci];
            uint32[] memory pm = new uint32[](n);
            pm[0] = 1; // simulate one signer having participated

            vm.resumeGasMetering();
            uint256 g = gasleft();
            bytes32 h = keccak256(abi.encode(pm));
            g = g - gasleft();
            vm.pauseGasMetering();

            _measure(string.concat("nodes=", vm.toString(n)), g);
            (h);
        }
    }

    // ─── Phase 8: DummyFeed vs real Feed publish cost ─────────────────────────

    function test_phase_feedPublish() public {
        vm.pauseGasMetering();
        console2.log("=== IFeed.publish() cost (the callee, not NodeRegistry) ===");

        DummyFeed feed = new DummyFeed();
        bytes memory value = abi.encodePacked(uint256(42e18));

        // First push: 0→nonzero SSTOREs (cold, new array slot)
        vm.resumeGasMetering();
        uint256 g = gasleft();
        feed.publish(IFeedStructs.Answer({value: value, timestamp: 1_000_001}));
        g = g - gasleft();
        vm.pauseGasMetering();
        _measure("first push  (0-to-nonzero SSTOREs)", g);

        // Second push: appends to already-grown array
        vm.resumeGasMetering();
        g = gasleft();
        feed.publish(IFeedStructs.Answer({value: value, timestamp: 1_000_002}));
        g = g - gasleft();
        vm.pauseGasMetering();
        _measure("second push (nonzero-to-nonzero SSTOREs)", g);
    }
}

// Minimal import to use IFeedStructs in the test directly.
import {IFeedStructs} from "../src/interfaces/IFeedStructs.sol";
