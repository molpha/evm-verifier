// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {MessageHashUtils} from "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

import {ERC165Checker} from "./libs/ERC165Checker.sol";
import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {IFeed} from "./interfaces/IFeed.sol";
import {IFeedRegistryStructs} from "./interfaces/IFeedRegistryStructs.sol";
// import {INodesRegistry} from "./interfaces/INodesRegistry.sol";
import {ISubscriptionRegistry} from "./interfaces/ISubscriptionRegistry.sol";
// import {ITreasury} from "./interfaces/ITreasury.sol";
import {INodeRegistry} from "./interfaces/INodeRegistry.sol";
import {IFeed} from "./interfaces/IFeed.sol";

// TODO: think about aggregator deactivation flow
contract Feed is IFeed, ERC165 {
    using ERC165Checker for address;
    using MessageHashUtils for bytes32;

    IAccessControlManager internal immutable _accessControlManager;
    // INodesRegistry internal immutable _nodesRegistry;
    ISubscriptionRegistry internal immutable _subscriptionRegistry;
    // ITreasury internal immutable _treasury;
    INodeRegistry internal immutable _nodeRegistry;

    uint256 internal immutable _minSignaturesThresholdImmutable; // we use immutable for public feeds, for personal feeds this value is 0
    uint256 internal _minSignaturesThreshold; // we use storage for personal feeds, for public feeds this value is 0

    Answer[] internal _answers;

    modifier onlyValidConsumer() {
        // we allow calls from EOA cause data is accessible externally anyway
        // we allow calls from nodes cause they may need to check data
        if (
            !_subscriptionRegistry.isSubscribed(msg.sender, address(this)) && tx.origin != msg.sender
                // && _pubKeys[msg.sender].isZeroPoint()
        ) {
            revert NotSubscribed(msg.sender);
        }
        _;
    }

    modifier onlyPublisher() {
        // if (msg.sender != address(_publisher)) {
        //     revert NotPublisher (msg.sender);
        // }
        _;
    }

    modifier onlyFeedManager() {
        _accessControlManager.verifyFeedManager(msg.sender);
        _;
    }

    constructor(
        IFeedRegistryStructs.FeedType feedType,
        IAccessControlManager accessControlManager,
        INodeRegistry nodeRegistry,
        ISubscriptionRegistry subscriptionRegistry,
        uint256 minSignaturesThreshold // must be 0 for public feeds; TODO: think about this and implement properly
    ) {
        address(accessControlManager).shouldSupport(type(IAccessControlManager).interfaceId);
        address(nodeRegistry).shouldSupport(type(INodeRegistry).interfaceId);
        address(subscriptionRegistry).shouldSupport(type(ISubscriptionRegistry).interfaceId);

        _accessControlManager = accessControlManager;
        _subscriptionRegistry = subscriptionRegistry;
        _nodeRegistry = nodeRegistry;
        _minSignaturesThresholdImmutable = minSignaturesThreshold;
        // _minSignaturesThreshold = minSignaturesThreshold;
    }

    // just idea noted here. for public feeds minSignaturesThreshold is a constant value, 
    // so we can set it in constructor and have one less storage slot to read during publishAnswer
    // but for personal feeds it can be changed later, so concep is to use immutable when it's set in constructor
    // TODO: think about this and implement properly
    function setMinSignaturesThreshold(uint256 minSignaturesThreshold) external override onlyFeedManager {
        require(_minSignaturesThresholdImmutable == 0, ImmutableThreshold());
        _minSignaturesThreshold = minSignaturesThreshold;
    }

    /// @inheritdoc IFeed
    function publishAnswer(Answer calldata answer, INodeRegistry.SchnorrSignature calldata schnorrData) external {
        _nodeRegistry.verifySignature(_constructMessage(answer), schnorrData, _getMinSignaturesThreshold());

        _answers.push(answer);
        emit LogAnswerPublished(answer.value, answer.timestamp);
    }

    /// @inheritdoc IFeed
    function getLatest() external view override onlyValidConsumer returns (bytes memory value, uint256 timestamp) {
        uint256 length = _answers.length;
        if (length == 0) {
            return ("", 0);
        }

        Answer memory latest = _answers[length - 1];
        return (latest.value, latest.timestamp);
    }

    /// @inheritdoc IFeed
    function getEntry(uint256 roundId)
        external
        view
        override
        onlyValidConsumer
        returns (bytes memory value, uint256 timestamp)
    {
        Answer memory a = _answers[roundId];
        return (a.value, a.timestamp);
    }

    function getLastUpdated() external view override returns (uint256 timestamp) {
        uint256 length = _answers.length;
        if (length == 0) {
            return 0;
        }
        return _answers[length - 1].timestamp;
    }

    /// @inheritdoc IFeed
    function getSubscriptionRegistry() external view override returns (ISubscriptionRegistry subscriptionRegistry) {
        return _subscriptionRegistry;
    }

    /// @inheritdoc IFeed
    function getMinSignaturesThreshold() external view override returns (uint256 minSignaturesThreshold) {
        return _getMinSignaturesThreshold();
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IFeed).interfaceId || super.supportsInterface(interfaceId);
    }

    function _constructMessage(Answer calldata answer) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), answer.value, answer.timestamp)).toEthSignedMessageHash();
    }

    // check if immutable is set, if not - use the one from storage
    function _getMinSignaturesThreshold() internal view returns (uint256) {
        return _minSignaturesThresholdImmutable > 0 ? _minSignaturesThresholdImmutable : _minSignaturesThreshold;
    }

    function _validateAnswer(Answer calldata answer) internal view {
        if (keccak256(answer.value) == keccak256(bytes(""))) {
            revert ZeroValue();
        }
        uint256 length = _answers.length;
        if (length > 0 && answer.timestamp <= _answers[length - 1].timestamp) {
            revert PastTimestamp(answer.timestamp, _answers[length - 1].timestamp);
        }
        if (answer.timestamp > block.timestamp) {
            revert FutureTimestamp(answer.timestamp, block.timestamp);
        }
    }
}