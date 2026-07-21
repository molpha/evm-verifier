// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {console2} from "forge-std/Test.sol";

import {Verifier} from "../../src/Verifier.sol";
import {IVerifier} from "../../src/interfaces/IVerifier.sol";
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
        IVerifier.DataUpdate firstUpdate;
        IVerifier.SchnorrSignature firstSignature;
        IVerifier.DataUpdate secondUpdate;
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
        benchmark.firstCalldataCost =
            _calldataCost(abi.encodeCall(IVerifier.verify, (benchmark.firstUpdate, benchmark.firstSignature)));
        benchmark.secondCalldataCost =
            _calldataCost(abi.encodeCall(IVerifier.verify, (benchmark.secondUpdate, benchmark.secondSignature)));

        vm.resumeGasMetering();
    }

    function _run(Scenario memory scenario) internal {
        BenchmarkSetup memory benchmark = _setup(scenario);

        uint256 gasBefore = gasleft();
        bool firstVerified = benchmark.target.verify(benchmark.firstUpdate, benchmark.firstSignature);
        uint256 coldExecution = gasBefore - gasleft();

        gasBefore = gasleft();
        bool secondVerified = benchmark.target.verify(benchmark.secondUpdate, benchmark.secondSignature);
        uint256 warmExecution = gasBefore - gasleft();

        vm.pauseGasMetering();
        assertTrue(firstVerified);
        assertTrue(secondVerified);
        console2.log(
            string.concat("nodes=", vm.toString(scenario.nodeCount), " signers=", vm.toString(scenario.threshold))
        );
        console2.log(
            string.concat(
                "  cold | execution=",
                vm.toString(coldExecution),
                " calldata=",
                vm.toString(benchmark.firstCalldataCost),
                " total=",
                vm.toString(coldExecution + benchmark.firstCalldataCost + BASE_TRANSACTION_GAS)
            )
        );
        console2.log(
            string.concat(
                "  warm | execution=",
                vm.toString(warmExecution),
                " calldata=",
                vm.toString(benchmark.secondCalldataCost),
                " total=",
                vm.toString(warmExecution + benchmark.secondCalldataCost + BASE_TRANSACTION_GAS)
            )
        );
        vm.resumeGasMetering();
    }

    function testGas_verifyScenarios() public {
        Scenario[17] memory scenarios = [
            Scenario({nodeCount: 128, threshold: 1}),
            Scenario({nodeCount: 128, threshold: 3}),
            Scenario({nodeCount: 128, threshold: 5}),
            Scenario({nodeCount: 128, threshold: 9}),
            Scenario({nodeCount: 128, threshold: 18}),
            Scenario({nodeCount: 5, threshold: 3}),
            Scenario({nodeCount: 10, threshold: 5}),
            Scenario({nodeCount: 12, threshold: 3}),
            Scenario({nodeCount: 12, threshold: 8}),
            Scenario({nodeCount: 20, threshold: 8}),
            Scenario({nodeCount: 32, threshold: 8}),
            Scenario({nodeCount: 32, threshold: 18}),
            Scenario({nodeCount: 64, threshold: 18}),
            Scenario({nodeCount: 64, threshold: 32}),
            Scenario({nodeCount: 128, threshold: 32}),
            Scenario({nodeCount: 256, threshold: 18}),
            Scenario({nodeCount: 256, threshold: 64})
        ];

        for (uint256 i; i < scenarios.length; ++i) {
            _run(scenarios[i]);
        }
    }
}
