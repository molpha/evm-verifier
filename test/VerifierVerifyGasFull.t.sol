// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test, console2} from "forge-std/Test.sol";
import {MessageHashUtils} from "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

import {Verifier} from "../src/Verifier.sol";
import {IVerifier} from "../src/interfaces/IVerifier.sol";
import {LibSecp256k1} from "../src/libs/LibSecp256k1.sol";
import {NodeGroupBitmapLib} from "../src/libs/NodeGroupBitmapLib.sol";
import {LibSchnorrTestSign} from "./libs/LibSchnorrTestSign.sol";

/// @title VerifierVerifyGasFullTest
///
/// Measures the on-chain cost of `Verifier.verify()` similarly to `NodeRegistryPublishGasFull`:
///
///   execution   — gasleft() delta around `verify()` (full call tree).
///
///   calldata    — from `abi.encodeCall()` bytes priced at EIP-2028 rates
///                 (4 gas/zero byte, 16 gas/nonzero byte).
///
///   base tx     — 21,000 gas (fixed per EIP-2).
///
///   total est.  — execution + calldata + base tx.
///
/// Two synthetic rounds use different `canonicalTimestamp` / payload so selection seeds and
/// Schnorr messages differ; round 2 tends to hit warmer bytecode reads than round 1.
///
/// Run:
///   forge test --match-path test/VerifierVerifyGasFull.t.sol -vv
///
/// @dev Do **not** rely on printed `exec` / TOTAL next to `--gas-report` or `--isolate`.
///      Foundry runs isolated external calls under `--gas-report`, so `gasleft()` deltas and
///      per-test `(gas: …)` diverge from a normal single-tx framing — use plain `forge test`
///      for these numbers, and a separate `--gas-report` pass for the contract table only.
contract VerifierVerifyGasFullTest is Test {
    using MessageHashUtils for bytes32;
    using LibSecp256k1 for LibSecp256k1.Point;

    uint256 constant BASE_TX_GAS = 21_000;

    // Matches private constants in `Verifier.sol`.
    bytes32 internal constant POP_DOMAIN = keccak256("MOLPHA_VALIDATOR_V1");
    bytes32 internal constant MESSAGE_PREFIX = keccak256("MOLPHA_MESSAGE_V1");
    bytes32 internal constant SELECTION_SEED_PREFIX = keccak256("MOLPHA_SELECTION_V1");

    struct VerifyCall {
        IVerifier.DataUpdate dataUpdate;
        IVerifier.SchnorrSignature schnorr;
    }

    struct Scenario {
        uint256 nodeCount;
        uint256 threshold;
    }

    struct FullSetup {
        Verifier reg;
        VerifyCall call1;
        VerifyCall call2;
        uint256 calldataCost1;
        uint256 calldataCost2;
    }

    function _secret(uint256 slot) internal pure returns (uint256) {
        return (uint256(keccak256(abi.encodePacked("MOLPHA_VALIDATOR_VERIFY_GAS", slot))) % (LibSecp256k1.Q() - 1)) + 1;
    }

    function _popSig(address validatorAddr, bytes memory compressedPubKey, uint256 sk)
        internal
        pure
        returns (IVerifier.SchnorrProof memory pop)
    {
        bytes32 digest =
            keccak256(abi.encodePacked(POP_DOMAIN, validatorAddr, compressedPubKey));
        LibSecp256k1.Point memory pubKey = LibSecp256k1.mulAffine(LibSecp256k1.G(), sk);
        (bytes32 sig, address cmt) = LibSchnorrTestSign.sign(pubKey, sk, digest, 0);
        pop = IVerifier.SchnorrProof({signature: sig, commitment: cmt});
    }

    function _registeredNodeCount(Verifier validator) internal view returns (uint256 n) {
        n = validator.getTotalNodes();
    }

    function _selectionSeed(IVerifier.DataUpdate memory du) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(SELECTION_SEED_PREFIX, du.feedId, du.registryVersion, du.canonicalTimestamp));
    }

    function _constructMessage(IVerifier.DataUpdate memory du, uint256 signersBitmap)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
                abi.encodePacked(
                    MESSAGE_PREFIX,
                    du.feedId,
                    du.registryVersion,
                    du.signaturesRequired,
                    signersBitmap,
                    du.value,
                    du.canonicalTimestamp
                )
            );
    }

    function _pickSignerIndices(uint256 bitmap, uint256 nRegistered, uint256 need)
        internal
        pure
        returns (uint256[] memory idx1based)
    {
        idx1based = new uint256[](need);
        uint256 found;
        for (uint256 pos = 0; pos < nRegistered && found < need; ++pos) {
            if (bitmap & (uint256(1) << pos) != 0) {
                idx1based[found++] = pos + 1;
            }
        }
        require(found == need, "pickSignerIndices");
    }

    function _pubkeysForIndices(LibSecp256k1.Point[] memory allPubkeys, uint256[] memory idx1based)
        internal
        pure
        returns (LibSecp256k1.Point[] memory pts)
    {
        pts = new LibSecp256k1.Point[](idx1based.length);
        for (uint256 i; i < idx1based.length; ++i) {
            pts[i] = allPubkeys[idx1based[i] - 1];
        }
    }

    function _sumPubkeys(LibSecp256k1.Point[] memory pts) internal view returns (LibSecp256k1.Point memory agg) {
        agg = pts[0];
        for (uint256 i = 1; i < pts.length; ++i) {
            (uint256 ax, uint256 ay, uint256 az) = LibSecp256k1.addAffinePointToXYZ(agg.x, agg.y, 1, pts[i].x, pts[i].y);
            agg = LibSecp256k1.toAffineModexpXYZ(ax, ay, az);
        }
    }

    function _sumSecrets(uint256[] memory allSecrets, uint256[] memory idx1based)
        internal
        pure
        returns (uint256 skEff)
    {
        uint256 Q = LibSecp256k1.Q();
        for (uint256 i; i < idx1based.length; ++i) {
            skEff = addmod(skEff, allSecrets[idx1based[i] - 1], Q);
        }
    }

    function _buildVerifyCall(
        Verifier validator,
        LibSecp256k1.Point[] memory allPubkeys,
        uint256[] memory allSecrets,
        uint256 threshold,
        bytes32 feedId,
        bytes32 value,
        uint64 canonicalTimestamp
    ) internal view returns (VerifyCall memory c) {
        c.dataUpdate = IVerifier.DataUpdate({
            feedId: feedId,
            registryVersion: uint32(validator.getRegistryVersion()),
            signaturesRequired: uint32(threshold),
            value: value,
            canonicalTimestamp: canonicalTimestamp
        });

        uint256 nReg = _registeredNodeCount(validator);
        uint256 grpSize = threshold + validator.redundancyBuffer();
        bytes32 selSeed = _selectionSeed(c.dataUpdate);
        uint256 selectionBitmap = NodeGroupBitmapLib.derive(selSeed, nReg, grpSize);

        uint256[] memory idxs = _pickSignerIndices(selectionBitmap, nReg, threshold);
        LibSecp256k1.Point[] memory pts = _pubkeysForIndices(allPubkeys, idxs);
        LibSecp256k1.Point memory aggPk = _sumPubkeys(pts);

        uint256 signerBits;
        for (uint256 i; i < idxs.length; ++i) {
            signerBits |= uint256(1) << (idxs[i] - 1);
        }

        bytes32 msgHash = _constructMessage(c.dataUpdate, signerBits);
        uint256 skEff = _sumSecrets(allSecrets, idxs);
        (bytes32 sig, address cmt) = LibSchnorrTestSign.sign(aggPk, skEff, msgHash, 0);

        c.schnorr = IVerifier.SchnorrSignature({signature: sig, commitment: cmt, signersBitmap: signerBits});
    }

    /// @dev Prices calldata per EIP-2028: 4 gas per zero byte, 16 gas per nonzero byte.
    function _calldataCost(bytes memory data) internal pure returns (uint256 cost) {
        for (uint256 i; i < data.length; ++i) {
            cost += (data[i] == 0) ? 4 : 16;
        }
    }

    function _setup(Scenario memory s) internal returns (FullSetup memory fs) {
        vm.pauseGasMetering();

        fs.reg = new Verifier(address(this), 2);

        LibSecp256k1.Point[] memory allPubkeys = new LibSecp256k1.Point[](s.nodeCount);
        uint256[] memory allSecrets = new uint256[](s.nodeCount);
        for (uint256 i; i < s.nodeCount; ++i) {
            allSecrets[i] = _secret(i + 1);
            allPubkeys[i] = LibSecp256k1.mulAffine(LibSecp256k1.G(), allSecrets[i]);
            bytes memory compressed = LibSecp256k1.compress(allPubkeys[i]);
            fs.reg.addNode(compressed, _popSig(address(fs.reg), compressed, allSecrets[i]));
        }

        bytes32 feedId = bytes32(uint256(keccak256("VALIDATOR_VERIFY_GAS_JOB")));

        vm.warp(1_000_000);
        uint64 tsBase = uint64(block.timestamp);

        fs.call1 = _buildVerifyCall(
            fs.reg,
            allPubkeys,
            allSecrets,
            s.threshold,
            feedId,
            bytes32(uint256(1)),
            tsBase + 1
        );

        fs.call2 = _buildVerifyCall(
            fs.reg,
            allPubkeys,
            allSecrets,
            s.threshold,
            feedId,
            bytes32(uint256(2)),
            tsBase + 2
        );

        fs.calldataCost1 = _calldataCost(abi.encodeCall(IVerifier.verify, (fs.call1.dataUpdate, fs.call1.schnorr)));
        fs.calldataCost2 = _calldataCost(abi.encodeCall(IVerifier.verify, (fs.call2.dataUpdate, fs.call2.schnorr)));

        vm.resumeGasMetering();
    }

    function _runBench(Scenario memory s) internal {
        FullSetup memory fs = _setup(s);

        uint256 gasBefore = gasleft();
        fs.reg.verify(fs.call1.dataUpdate, fs.call1.schnorr);
        uint256 exec1 = gasBefore - gasleft();

        gasBefore = gasleft();
        fs.reg.verify(fs.call2.dataUpdate, fs.call2.schnorr);
        uint256 exec2 = gasBefore - gasleft();

        vm.pauseGasMetering();

        uint256 total1 = exec1 + fs.calldataCost1 + BASE_TX_GAS;
        uint256 total2 = exec2 + fs.calldataCost2 + BASE_TX_GAS;

        console2.log(string.concat("nodes=", vm.toString(s.nodeCount), "  signers=", vm.toString(s.threshold)));
        console2.log(
            string.concat(
                "  Round 1 (cold)  | exec: ",
                vm.toString(exec1),
                "  calldata: ",
                vm.toString(fs.calldataCost1),
                "  base: ",
                vm.toString(BASE_TX_GAS),
                "  TOTAL: ",
                vm.toString(total1)
            )
        );
        console2.log(
            string.concat(
                "  Round 2 (warm)  | exec: ",
                vm.toString(exec2),
                "  calldata: ",
                vm.toString(fs.calldataCost2),
                "  base: ",
                vm.toString(BASE_TX_GAS),
                "  TOTAL: ",
                vm.toString(total2)
            )
        );

        vm.resumeGasMetering();
    }

    function test_full_nodes03_signers01() public {
        _runBench(Scenario({nodeCount: 12, threshold: 3}));
        _runBench(Scenario({nodeCount: 12, threshold: 8}));
        _runBench(Scenario({nodeCount: 32, threshold: 8}));
        _runBench(Scenario({nodeCount: 32, threshold: 18}));
        _runBench(Scenario({nodeCount: 64, threshold: 18}));
        _runBench(Scenario({nodeCount: 64, threshold: 32}));
        _runBench(Scenario({nodeCount: 128, threshold: 18}));
        _runBench(Scenario({nodeCount: 128, threshold: 32}));
        _runBench(Scenario({nodeCount: 256, threshold: 18}));
        _runBench(Scenario({nodeCount: 256, threshold: 64}));
    }
}
