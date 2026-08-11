// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {console2} from "forge-std/Test.sol";
import {SSTORE2} from "solady/utils/SSTORE2.sol";

import {Verifier} from "../../src/Verifier.sol";
import {IVerifier} from "../../src/interfaces/IVerifier.sol";
import {LibSecp256k1} from "../../src/libs/LibSecp256k1.sol";
import {PubkeyBlobLib} from "../../src/libs/PubkeyBlobLib.sol";
import {VerifierTestBase} from "../shared/VerifierTestBase.sol";

/// @dev Run with `FOUNDRY_PROFILE=gas forge test -vv`.
contract VerifierRegistryGasTest is VerifierTestBase {
    using LibSecp256k1 for LibSecp256k1.Point;
    using PubkeyBlobLib for bytes;

    uint256 internal constant BASE_TRANSACTION_GAS = 21_000;

    struct AddScenario {
        uint256 nodeCountBefore;
        bool warm;
    }

    struct RemoveScenario {
        uint256 nodeCount;
        uint256 removeIndex;
        uint256 secondRemoveIndex;
        bool warm;
    }

    struct NodeCred {
        bytes compressedPubKey;
        IVerifier.SchnorrProof pop;
    }

    struct AddBenchmarkSetup {
        Verifier target;
        NodeCred first;
        NodeCred second;
        uint256 expectedNodeCount;
        bool warm;
        uint256 firstCalldataCost;
        uint256 secondCalldataCost;
    }

    struct RemoveBenchmarkSetup {
        Verifier target;
        address firstRemoveNode;
        address secondRemoveNode;
        uint256 firstRemoveIndex;
        uint256 secondRemoveIndex;
        uint256 expectedNodeCount;
        uint256 firstCalldataCost;
        uint256 secondCalldataCost;
    }

    function _calldataCost(bytes memory data) internal pure returns (uint256 cost) {
        for (uint256 i; i < data.length; ++i) {
            cost += data[i] == 0 ? 4 : 16;
        }
    }

    function _nodeCred(Verifier target, uint256 slot) internal view returns (NodeCred memory cred) {
        uint256 secret = _secret(slot);
        LibSecp256k1.Point memory pubkey = LibSecp256k1.mulAffine(LibSecp256k1.G(), secret);
        cred.compressedPubKey = LibSecp256k1.compress(pubkey);
        cred.pop = _proofOfPossession(address(target), cred.compressedPubKey, secret);
    }

    function _setupAdd(AddScenario memory scenario) internal returns (AddBenchmarkSetup memory benchmark) {
        vm.pauseGasMetering();

        benchmark.target = new Verifier(address(this), 2);
        if (scenario.nodeCountBefore > 0) {
            _addNodes(benchmark.target, scenario.nodeCountBefore);
        }

        uint256 firstSlot = scenario.nodeCountBefore + 1;
        benchmark.expectedNodeCount = scenario.warm ? scenario.nodeCountBefore + 2 : scenario.nodeCountBefore + 1;
        benchmark.warm = scenario.warm;
        benchmark.first = _nodeCred(benchmark.target, firstSlot);
        benchmark.second = _nodeCred(benchmark.target, firstSlot + 1);
        benchmark.firstCalldataCost =
            _calldataCost(abi.encodeCall(IVerifier.addNode, (benchmark.first.compressedPubKey, benchmark.first.pop)));
        benchmark.secondCalldataCost =
            _calldataCost(abi.encodeCall(IVerifier.addNode, (benchmark.second.compressedPubKey, benchmark.second.pop)));

        vm.resumeGasMetering();
    }

    function _measureAdd(AddBenchmarkSetup memory benchmark) private returns (uint256 cold, uint256 warm) {
        vm.cool(address(benchmark.target));

        uint256 gasBefore = gasleft();
        benchmark.target.addNode(benchmark.first.compressedPubKey, benchmark.first.pop);
        cold = gasBefore - gasleft();

        if (benchmark.warm) {
            gasBefore = gasleft();
            benchmark.target.addNode(benchmark.second.compressedPubKey, benchmark.second.pop);
            warm = gasBefore - gasleft();
        }

        vm.pauseGasMetering();
        assertEq(benchmark.target.getTotalNodes(), benchmark.expectedNodeCount);
        vm.resumeGasMetering();
    }

    function _runAdd(AddScenario memory scenario) internal {
        AddBenchmarkSetup memory benchmark = _setupAdd(scenario);
        (uint256 cold, uint256 warm) = _measureAdd(benchmark);

        vm.pauseGasMetering();
        console2.log(
            string.concat(
                "addNode nodesBefore=", vm.toString(scenario.nodeCountBefore), scenario.warm ? "" : " (cold only)"
            )
        );
        _logMeasurement("  cold execution=", cold, benchmark.firstCalldataCost);
        if (scenario.warm) {
            _logMeasurement("       execution=", warm, benchmark.secondCalldataCost);
        }
        vm.resumeGasMetering();
    }

    function _setupRemove(RemoveScenario memory scenario) internal returns (RemoveBenchmarkSetup memory benchmark) {
        vm.pauseGasMetering();

        benchmark.target = new Verifier(address(this), 2);
        _addNodes(benchmark.target, scenario.nodeCount);
        benchmark.firstRemoveIndex = scenario.removeIndex;
        benchmark.secondRemoveIndex = scenario.secondRemoveIndex;
        benchmark.firstRemoveNode = pubkeys[scenario.removeIndex].toAddress();
        benchmark.secondRemoveNode = pubkeys[scenario.secondRemoveIndex].toAddress();
        benchmark.expectedNodeCount = scenario.warm ? scenario.nodeCount - 2 : scenario.nodeCount - 1;
        benchmark.firstCalldataCost = _calldataCost(
            abi.encodeCall(IVerifier.removeNode, (benchmark.firstRemoveNode, benchmark.firstRemoveIndex))
        );
        benchmark.secondCalldataCost = _calldataCost(
            abi.encodeCall(IVerifier.removeNode, (benchmark.secondRemoveNode, benchmark.secondRemoveIndex))
        );

        vm.resumeGasMetering();
    }

    function _measureRemove(RemoveBenchmarkSetup memory benchmark, bool warm)
        private
        returns (uint256 cold, uint256 warmGas)
    {
        vm.cool(address(benchmark.target));

        uint256 gasBefore = gasleft();
        benchmark.target.removeNode(benchmark.firstRemoveNode, benchmark.firstRemoveIndex);
        cold = gasBefore - gasleft();

        if (warm) {
            address secondNode =
                SSTORE2.read(benchmark.target.getRegistryPointer()).getNode(benchmark.secondRemoveIndex).toAddress();
            gasBefore = gasleft();
            benchmark.target.removeNode(secondNode, benchmark.secondRemoveIndex);
            warmGas = gasBefore - gasleft();
        }

        vm.pauseGasMetering();
        assertEq(benchmark.target.getTotalNodes(), benchmark.expectedNodeCount);
        vm.resumeGasMetering();
    }

    function _runRemove(RemoveScenario memory scenario) internal {
        RemoveBenchmarkSetup memory benchmark = _setupRemove(scenario);
        (uint256 cold, uint256 warm) = _measureRemove(benchmark, scenario.warm);

        vm.pauseGasMetering();
        console2.log(
            string.concat(
                "removeNode nodes=",
                vm.toString(scenario.nodeCount),
                " index=",
                vm.toString(scenario.removeIndex),
                scenario.warm ? "" : " (cold only)"
            )
        );
        _logMeasurement("  cold execution=", cold, benchmark.firstCalldataCost);
        if (scenario.warm) {
            _logMeasurement("       execution=", warm, benchmark.secondCalldataCost);
        }
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

    function testGas_addNodeScenarios() public {
        AddScenario[5] memory scenarios = [
            AddScenario({nodeCountBefore: 0, warm: true}),
            AddScenario({nodeCountBefore: 1, warm: true}),
            AddScenario({nodeCountBefore: 8, warm: true}),
            AddScenario({nodeCountBefore: 254, warm: true}),
            AddScenario({nodeCountBefore: 255, warm: false})
        ];

        for (uint256 i; i < scenarios.length; ++i) {
            _runAdd(scenarios[i]);
        }
    }

    function testGas_removeNodeScenarios() public {
        RemoveScenario[8] memory scenarios = [
            RemoveScenario({nodeCount: 1, removeIndex: 0, secondRemoveIndex: 0, warm: false}),
            RemoveScenario({nodeCount: 2, removeIndex: 1, secondRemoveIndex: 0, warm: true}),
            RemoveScenario({nodeCount: 8, removeIndex: 7, secondRemoveIndex: 6, warm: true}),
            RemoveScenario({nodeCount: 8, removeIndex: 0, secondRemoveIndex: 0, warm: true}),
            RemoveScenario({nodeCount: 8, removeIndex: 4, secondRemoveIndex: 4, warm: true}),
            RemoveScenario({nodeCount: 128, removeIndex: 4, secondRemoveIndex: 4, warm: true}),
            RemoveScenario({nodeCount: 256, removeIndex: 255, secondRemoveIndex: 254, warm: true}),
            RemoveScenario({nodeCount: 256, removeIndex: 0, secondRemoveIndex: 0, warm: true})
        ];

        for (uint256 i; i < scenarios.length; ++i) {
            _runRemove(scenarios[i]);
        }
    }
}
