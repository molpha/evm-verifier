// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFeed} from "../../src/interfaces/IFeed.sol";
import {IFeedStructs} from "../../src/interfaces/IFeedStructs.sol";
import {ISubscriptionRegistry} from "../../src/interfaces/ISubscriptionRegistry.sol";
import {INodeRegistry} from "../../src/interfaces/INodeRegistry.sol";
import {INodeRegistryStructs} from "../../src/interfaces/INodeRegistryStructs.sol";

contract DummyFeed is IFeed {
    IFeedStructs.Answer[] internal answers;
    uint256 internal _minSignaturesThreshold;

    function initialize(bytes32 metadataHash, uint256 minSignaturesThresholdParam) external {
        _minSignaturesThreshold = minSignaturesThresholdParam;
    }

    function publishAnswer(
        IFeedStructs.Answer calldata answer,
        INodeRegistryStructs.SchnorrSignature calldata
    ) external {
        answers.push(answer);
    }

    function setMinSignaturesThreshold(uint256 minSignaturesThresholdParam) external {
        _minSignaturesThreshold = minSignaturesThresholdParam;
    }

    function getMinSignaturesThreshold() external view returns (uint256) {
        return _minSignaturesThreshold;
    }

    function getLatest() external view returns (bytes memory value, uint256 timestamp) {
        if (answers.length == 0) return ("", 0);
        IFeedStructs.Answer memory a = answers[answers.length - 1];
        return (a.value, a.timestamp);
    }

    function getLastUpdated() external view returns (uint256 timestamp) {
        if (answers.length == 0) return 0;
        return answers[answers.length - 1].timestamp;
    }

    function getSubscriptionRegistry() external view returns (ISubscriptionRegistry) {
        return ISubscriptionRegistry(address(0));
    }

    function getEntry(uint256 index) external view returns (bytes memory, uint256) {
        IFeedStructs.Answer memory a = answers[index];
        return (a.value, a.timestamp);
    }

    function getMetadataHash() external view returns (bytes32) {
        return bytes32(0);
    }

    function getConfig() external view returns (uint256, uint256) {
        return (0, 0);
    }

    function getFrequency() external view returns (uint256) {
        return 0;
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return interfaceId == type(IFeed).interfaceId;
    }
}
