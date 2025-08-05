// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";

import {ERC165Checker} from "./libs/ERC165Checker.sol";
import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {IFeed} from "./interfaces/IFeed.sol";

// TODO: think about aggregator deactivation flow
contract Feed is IFeed, ERC165 {
    using ERC165Checker for address;

    uint256 internal constant MAX_FREQUENCY = 1 days;
    uint256 internal constant MIN_FREQUENCY = 1 minutes;

    IAccessControlManager internal _accessControlManager;

    address internal immutable _owner;
    FeedType internal immutable _feedType;
    bool internal immutable _isFree;
    bytes32 internal immutable _dataSourceId;

    uint256 internal _frequency;
    uint256 internal _signaturesRequired;
    string internal _ipfsCID;

    Answer[] internal _answers;
    mapping(address => uint256) internal _consumers;

    modifier onlyValidConsumer() {
        require(
            _isFree ||
                msg.sender == tx.origin ||
                _consumers[msg.sender] >= block.timestamp,
            NotConsumer(msg.sender)
        );
        _;
    }

    modifier onlyFeedOwnerOrSubRegistry() {
        if (msg.sender != _owner) {
            _accessControlManager.verifySubscriptionRegistry(msg.sender);
        }
        _;
    }

    modifier onlyNodeRegistry() {
        _accessControlManager.verifyNodeRegistry(msg.sender);
        _;
    }

    modifier onlyFeedRegistry() {
        _accessControlManager.verifyFeedRegistry(msg.sender);
        _;
    }

    constructor(CreateFeedParams memory params) {
        _validateFeedConfig(params);

        _accessControlManager = IAccessControlManager(params.accessControlManager);
        _owner = params.owner;
        _feedType = params.feedType;
        _frequency = params.frequency;
        _signaturesRequired = params.signaturesRequired;
        _ipfsCID = params.ipfsCID;
        _isFree = params.consumerPricePerSecondScaled == 0;
        _dataSourceId = params.dataSourceId;
    }

    /// @inheritdoc IFeed
    function publish(Answer calldata answer) external onlyNodeRegistry {
        require(answer.value.length > 0, ZeroValue());
        uint256 lastUpdated = _getLastUpdated();
        require(
            answer.timestamp > lastUpdated,
            PastTimestamp(answer.timestamp, lastUpdated)
        );
        require(
            answer.timestamp <= block.timestamp,
            FutureTimestamp(answer.timestamp, block.timestamp)
        );

        _answers.push(answer);
        emit LogAnswerPublished(answer.value, answer.timestamp);
    }

    /// @inheritdoc IFeed
    function addConsumer(address consumer, uint256 dueTime) external override onlyFeedOwnerOrSubRegistry {
        require(dueTime > block.timestamp, PastDueTime(dueTime));
        _consumers[consumer] = dueTime;
    }

    /// @inheritdoc IFeed
    function removeConsumer(address consumer) external override onlyFeedOwnerOrSubRegistry {
        if (_consumers[consumer] == 0) revert NotConsumer(consumer);
        delete _consumers[consumer];
    }

    /// @inheritdoc IFeed
    function setConsumers(
        address[] calldata consumersToAdd,
        uint256 dueTime,
        address[] calldata consumersToRemove
    ) external override onlyFeedOwnerOrSubRegistry {
        if (consumersToAdd.length > 0) {
            require(dueTime > block.timestamp, PastDueTime(dueTime));
            for (uint256 i = 0; i < consumersToAdd.length; i++) {
                _consumers[consumersToAdd[i]] = dueTime;
            }
        }

        if (consumersToRemove.length > 0) {
            for (uint256 i = 0; i < consumersToRemove.length; i++) {
                if (_consumers[consumersToRemove[i]] == 0) revert NotConsumer(consumersToRemove[i]);
                delete _consumers[consumersToRemove[i]];
            }
        }

        emit LogConsumersSet(consumersToAdd, dueTime, consumersToRemove);
    }

    /// @inheritdoc IFeed
    function updateFeedConfig(
        uint256 frequency,
        uint256 signaturesRequired,
        string calldata ipfsCID
    ) external override onlyFeedRegistry {
        require(
            frequency >= MIN_FREQUENCY && frequency <= MAX_FREQUENCY,
            InvalidFrequency(frequency)
        );
        require(
            signaturesRequired > 0,
            InvalidMinSignaturesThreshold(signaturesRequired)
        );
        require(
            keccak256(bytes(ipfsCID)) != keccak256(bytes("")),
            InvalidCID(ipfsCID)
        );

        if (frequency != _frequency) _frequency = frequency;
        if (signaturesRequired != _signaturesRequired) {
            _signaturesRequired = signaturesRequired;
        }
        if (keccak256(bytes(ipfsCID)) != keccak256(bytes(_ipfsCID))) {
            _ipfsCID = ipfsCID;
        }

        emit LogFeedConfigChanged(
            frequency,
            signaturesRequired,
            ipfsCID
        );
    }

    /// @inheritdoc IFeed
    function getLatest()
        external
        view
        override
        onlyValidConsumer
        returns (bytes memory value, uint256 timestamp)
    {
        uint256 length = _answers.length;
        if (length == 0) {
            return ("", 0);
        }
        return _getAnswer(length - 1);
    }

    /// @inheritdoc IFeed
    function getEntry(
        uint256 roundId
    )
        external
        view
        override
        onlyValidConsumer
        returns (bytes memory value, uint256 timestamp)
    {
        require(roundId < _answers.length, InvalidRoundId(roundId));
        return _getAnswer(roundId);
    }

    function getLastUpdated()
        external
        view
        override
        returns (uint256 lastUpdated)
    {
        lastUpdated = _getLastUpdated();
    }

    /// @inheritdoc IFeed
    function getMinSignaturesThreshold()
        external
        view
        override
        returns (uint256 signaturesRequired)
    {
        signaturesRequired = _signaturesRequired;
    }

    function getFrequency() external view override returns (uint256 frequency) {
        frequency = _frequency;
    }

    function getOwner() external view override returns (address owner) {
        owner = _owner;
    }

    function getFeedType() external view override returns (FeedType feedType) {
        feedType = _feedType;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(IFeed).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function _getAnswer(
        uint256 roundId
    ) internal view returns (bytes memory value, uint256 timestamp) {
        Answer memory a = _answers[roundId];
        return (a.value, a.timestamp);
    }

    function _getLastUpdated() internal view returns (uint256 lastUpdated) {
        uint256 length = _answers.length;
        lastUpdated = length > 0 ? _answers[length - 1].timestamp : 0;
    }

    function _validateFeedConfig(CreateFeedParams memory params) internal view {
        require(params.owner != address(0), ZeroAddress());
        params.accessControlManager.shouldSupport(
            type(IAccessControlManager).interfaceId
        );
        // only public feed can have consumer price
        require(params.consumerPricePerSecondScaled == 0 || params.feedType == FeedType.PUBLIC, NotPersonalFeed());

        require(
            params.frequency >= MIN_FREQUENCY && params.frequency <= MAX_FREQUENCY,
            InvalidFrequency(params.frequency)
        );
        require(
            params.signaturesRequired > 0,
            InvalidMinSignaturesThreshold(params.signaturesRequired)
        );
        require(
            keccak256(bytes(params.ipfsCID)) != keccak256(bytes("")),
            InvalidCID(params.ipfsCID)
        );
        require(params.dataSourceId != bytes32(0), InvalidDataSourceId(params.dataSourceId));
    }
}
