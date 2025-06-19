// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFeed} from "../../src/interfaces/IFeed.sol";
import {ISubscriptionsRegistry} from "../../src/interfaces/ISubscriptionsRegistry.sol";
import {INodesAggregator} from "../../src/interfaces/INodesAggregator.sol";

contract DummyFeed is IFeed {
    Answer[] internal answers;

    function initialize(bytes32 metadataHash, uint256 minSignaturesThreshold) external {}

    function publishAnswer(Answer calldata, INodesAggregator.SchnorrSignature calldata) external {}

    function getLatest() external view returns (bytes memory value, uint256 timestamp) {
        if (answers.length == 0) return ("", 0);
        Answer memory a = answers[answers.length - 1];
        return (a.value, a.timestamp);
    }

    function getLastUpdated() external view returns (uint256 timestamp) {
        if (answers.length == 0) return 0;
        return answers[answers.length - 1].timestamp;
    }

    function getSubscriptionsRegistry() external view returns (ISubscriptionsRegistry) {
        return ISubscriptionsRegistry(address(0));
    }

    function getEntry(uint256 index) external view returns (bytes memory, uint256) {
        Answer memory a = answers[index];
        return (a.value, a.timestamp);
    }

    function getMetadataHash() external view returns (bytes32) {
        return bytes32(0);
    }

    function getMinSignaturesThreshold() external view returns (uint256) {
        return 0;
    }
}
