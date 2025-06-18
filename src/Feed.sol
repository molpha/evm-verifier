// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {MessageHashUtils} from "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

import {ERC165Checker} from "./libs/ERC165Checker.sol";
import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {IFeed} from "./interfaces/IFeed.sol";
// import {INodesRegistry} from "./interfaces/INodesRegistry.sol";
import {ISubscriptionsRegistry} from "./interfaces/ISubscriptionsRegistry.sol";
// import {ITreasury} from "./interfaces/ITreasury.sol";
import {INodesAggregator} from "./interfaces/INodesAggregator.sol";
import {IFeed} from "./interfaces/IFeed.sol";

// TODO: think about aggregator deactivation flow
contract Feed is IFeed, ERC165 {
    using ERC165Checker for address;
    using MessageHashUtils for bytes32;

    uint256 internal constant MAX_NODES = 256; // it means we can have up to 31 nodes in the network (0 index is empty)

    IAccessControlManager internal immutable _accessControlManager;
    // INodesRegistry internal immutable _nodesRegistry;
    ISubscriptionsRegistry internal immutable _subsciptionsRegistry;
    // ITreasury internal immutable _treasury;
    INodesAggregator internal immutable _nodesAggregator;

    Answer[] internal _answers;

    uint256 public minSignaturesThreshold;

    // pointer to Nodes[] in SSTORE2, nodes[0] is empty cause we use 1-based indexing
    address internal _pointer;
    mapping(address => uint256) internal _nodeIndexes; // address => index in nodes array

    modifier onlyValidConsumer() {
        // we allow calls from EOA cause data is accessible externally anyway
        // we allow calls from nodes cause they may need to check data
        if (
            !_subsciptionsRegistry.isSubscribed(msg.sender, address(this)) && tx.origin != msg.sender
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

    constructor(
        IAccessControlManager accessControlManager,
        INodesAggregator nodesAggregator,
        ISubscriptionsRegistry subsciptionsRegistry
        // ITreasury treasury
    ) {
        // address(accessControlManager).shouldSupport(type(IAccessControlManager).interfaceId);
        // address(nodesRegistry).shouldSupport(type(INodesRegistry).interfaceId);
        // address(subsciptionsRegistry).shouldSupport(type(ISubscriptionsRegistry).interfaceId);
        // address(treasury).shouldSupport(type(ITreasury).interfaceId);

        _accessControlManager = accessControlManager;
        _subsciptionsRegistry = subsciptionsRegistry;
        _nodesAggregator = nodesAggregator;
    }

    /// @inheritdoc IFeed
    function publishAnswer(Answer calldata answer, INodesAggregator.SchnorrSignature calldata schnorrData) external {
        _nodesAggregator.verifySignature(_constructMessage(answer), schnorrData, minSignaturesThreshold);

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
    function getSubscriptionsRegistry() external view override returns (ISubscriptionsRegistry subscriptionsRegistry) {
        return _subsciptionsRegistry;
    }

    // /// @inheritdoc IFeed
    // function getTreasury() external view override returns (ITreasury treasury) {
    //     return _treasury;
    // }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IFeed).interfaceId || super.supportsInterface(interfaceId);
    }

    function _constructMessage(Answer calldata answer) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), answer.value, answer.timestamp)).toEthSignedMessageHash();
    }

    function _validateAnswer(Answer calldata answer) internal view {
        // if (answer.value == 0) {
        //     revert ZeroValue();
        // }
        uint256 length = _answers.length;
        if (length > 0 && answer.timestamp <= _answers[length - 1].timestamp) {
            revert PastTimestamp(answer.timestamp, _answers[length - 1].timestamp);
        }
        if (answer.timestamp > block.timestamp) {
            revert FutureTimestamp(answer.timestamp, block.timestamp);
        }
    }
}