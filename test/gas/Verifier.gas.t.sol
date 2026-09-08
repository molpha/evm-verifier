// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {console2} from "forge-std/Test.sol";

import {Verifier} from "../../src/Verifier.sol";
import {IVerifier} from "../../src/interfaces/IVerifier.sol";
import {VerifyCodes} from "../../src/libs/VerifyCodes.sol";
import {VerifierTestBase} from "../shared/VerifierTestBase.sol";

/// @dev Run with `FOUNDRY_PROFILE=gas forge test -vv`.
contract VerifierGasTest is VerifierTestBase {
    uint256 internal constant BASE_TRANSACTION_GAS = 21_000;

    struct Scenario {
        uint256 nodeCount;
        uint256 threshold;
    }

    struct BenchmarkSetup {
        Verifier target;
        IVerifier.AttestationPayload firstUpdate;
        IVerifier.SchnorrSignature firstSignature;
        IVerifier.AttestationPayload secondUpdate;
        IVerifier.SchnorrSignature secondSignature;
        uint256 firstCalldataCost;
        uint256 secondCalldataCost;
    }

    function _calldataCost(bytes memory data) internal pure returns (uint256 cost) {
        for (uint256 i; i < data.length; ++i) {
            cost += data[i] == 0 ? 4 : 16;
        }
    }

    function _setup(Scenario memory scenario) internal returns (BenchmarkSetup memory benchmark) {
        vm.pauseGasMetering();

        benchmark.target = new Verifier(address(this), 2);
        _addNodes(benchmark.target, scenario.nodeCount);
        (benchmark.firstUpdate, benchmark.firstSignature) = _buildVerifyCall(
            benchmark.target, scenario.threshold, keccak256("MOLPHA_VERIFY_GAS_JOB"), bytes32(uint256(1)), 1_700_000_001
        );
        (benchmark.secondUpdate, benchmark.secondSignature) = _buildVerifyCall(
            benchmark.target, scenario.threshold, keccak256("MOLPHA_VERIFY_GAS_JOB"), bytes32(uint256(2)), 1_700_000_002
        );
        benchmark.firstCalldataCost = _calldataCost(
            abi.encodeCall(IVerifier.verify, (_attestation(benchmark.firstUpdate, benchmark.firstSignature), 0))
        );
        benchmark.secondCalldataCost = _calldataCost(
            abi.encodeCall(IVerifier.verify, (_attestation(benchmark.secondUpdate, benchmark.secondSignature), 0))
        );

        vm.resumeGasMetering();
    }

    /// @dev The first call pays cold storage/account access — what a real first-in-block
    ///      transaction costs. The second is warm, and is the number comparable across
    ///      historical benchmark runs.
    function _measure(BenchmarkSetup memory benchmark) private returns (uint256 cold, uint256 warm) {
        // Undo the warming that `_setup` did, so the first call pays what production pays.
        vm.cool(address(benchmark.target));

        uint256 gasBefore = gasleft();
        (bool firstVerified, uint8 firstCode) =
            benchmark.target.verify(_attestation(benchmark.firstUpdate, benchmark.firstSignature), 0);
        cold = gasBefore - gasleft();

        gasBefore = gasleft();
        (bool secondVerified, uint8 secondCode) =
            benchmark.target.verify(_attestation(benchmark.secondUpdate, benchmark.secondSignature), 0);
        warm = gasBefore - gasleft();

        vm.pauseGasMetering();
        assertTrue(firstVerified);
        assertEq(firstCode, VerifyCodes.R_OK);
        assertTrue(secondVerified);
        assertEq(secondCode, VerifyCodes.R_OK);
        vm.resumeGasMetering();
    }

    function _run(Scenario memory scenario) internal {
        BenchmarkSetup memory benchmark = _setup(scenario);
        (uint256 cold, uint256 warm) = _measure(benchmark);

        vm.pauseGasMetering();
        console2.log(
            string.concat("nodes=", vm.toString(scenario.nodeCount), " signers=", vm.toString(scenario.threshold))
        );
        _logMeasurement("  cold execution=", cold, benchmark.firstCalldataCost);
        _logMeasurement("       execution=", warm, benchmark.secondCalldataCost);
        vm.resumeGasMetering();
    }

    function _logMeasurement(string memory label, uint256 execution, uint256 calldataCost) private view {
        console2.log(
            string.concat(
                label,
                vm.toString(execution),
                " calldata=",
                vm.toString(calldataCost),
                " total=",
                vm.toString(execution + calldataCost + BASE_TRANSACTION_GAS)
            )
        );
    }

    function testGas_verifyScenarios() public {
        Scenario[7] memory scenarios = [
            // Scenario({nodeCount: 1, threshold: 1}),
            Scenario({nodeCount: 8, threshold: 5}),
            Scenario({nodeCount: 256, threshold: 1}),
            Scenario({nodeCount: 256, threshold: 5}),
            Scenario({nodeCount: 256, threshold: 9}),
            Scenario({nodeCount: 256, threshold: 18}),
            Scenario({nodeCount: 256, threshold: 32}),
            Scenario({nodeCount: 256, threshold: 64})
        ];

        for (uint256 i; i < scenarios.length; ++i) {
            _run(scenarios[i]);
        }
    }
}
