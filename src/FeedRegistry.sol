// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

import {ERC165Checker} from "./libs/ERC165Checker.sol";
import {Feed} from "./Feed.sol";
import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {IFeed} from "./interfaces/IFeed.sol";
import {IFeedErrors} from "./interfaces/IFeedErrors.sol";
import {IFeedRegistry} from "./interfaces/IFeedRegistry.sol";
import {ISubscriptionRegistry} from "./interfaces/ISubscriptionRegistry.sol";
import {IPricingHelper} from "./interfaces/IPricingHelper.sol";
import {IDataSourceRegistry} from "./interfaces/IDataSourceRegistry.sol";

contract FeedRegistry is IFeedRegistry, ERC165, Initializable {
    using ERC165Checker for address;

    IAccessControlManager internal _accessControlManager;
    ISubscriptionRegistry internal _subscriptionRegistry;
    IPricingHelper internal _pricingHelper;
    IDataSourceRegistry internal _dataSourceRegistry;

    modifier onlyProtocolAdmin() {
        _accessControlManager.verifyProtocolAdmin(msg.sender);
        _;
    }

    function initialize(
        address accessControlManager,
        address subscriptionRegistry,
        address dataSourceRegistry
    ) external override initializer {
        accessControlManager.shouldSupport(
            type(IAccessControlManager).interfaceId
        );
        subscriptionRegistry.shouldSupport(
            type(ISubscriptionRegistry).interfaceId
        );
        dataSourceRegistry.shouldSupport(type(IDataSourceRegistry).interfaceId);

        _accessControlManager = IAccessControlManager(accessControlManager);
        _subscriptionRegistry = ISubscriptionRegistry(subscriptionRegistry);
        _dataSourceRegistry = IDataSourceRegistry(dataSourceRegistry);
    }

    function createFeed(
        CreateFeedParams calldata params,
        CreateDataSourceParams calldata dataSourceParams
    ) external override {
        _validateFeedConfig(params);

        bytes32 dataSourceId = _dataSourceRegistry.createDataSource(dataSourceParams.dataSource, dataSourceParams.signature);

        _createFeed(params, dataSourceId);
    }

    function createFeed(
        CreateFeedParams calldata params,
        bytes32 dataSourceId
    ) external override {
        _validateFeedConfig(params);

        IDataSourceRegistry.DataSource
            memory dataSource = _dataSourceRegistry.getDataSource(dataSourceId);
        require(
            dataSource.owner == msg.sender ||
                dataSource.dataSourceType ==
                IDataSourceRegistry.DataSourceType.Public,
            PrivateDataSource()
        );

        _createFeed(params, dataSourceId);
    }

    function updateFeed(
        address feed,
        uint256 frequency,
        uint256 signaturesRequired,
        string calldata ipfsCID
    ) external override {
        require(signaturesRequired > 0, InvalidFeedConfig());
        require(frequency > 0, InvalidFeedConfig());
        require(
            keccak256(bytes(ipfsCID)) != keccak256(bytes("")),
            InvalidFeedConfig()
        );

        IFeed(feed).updateFeedConfig(frequency, signaturesRequired, ipfsCID);
        _subscriptionRegistry.recalculateSubscription(feed);
    }

    function setAccessControlManager(
        address accessControlManager
    ) external override onlyProtocolAdmin {
        address(accessControlManager).shouldSupport(
            type(IAccessControlManager).interfaceId
        );
        _accessControlManager = IAccessControlManager(accessControlManager);
    }

    function setSubscriptionRegistry(
        address subscriptionRegistry
    ) external override onlyProtocolAdmin {
        address(subscriptionRegistry).shouldSupport(
            type(ISubscriptionRegistry).interfaceId
        );
        _subscriptionRegistry = ISubscriptionRegistry(subscriptionRegistry);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(IFeedRegistry).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function _validateFeedConfig(CreateFeedParams calldata params) internal view {
        require(params.minSignaturesThreshold > 0, InvalidFeedConfig());
        require(params.frequency > 0, InvalidFeedConfig());
        require(
            keccak256(bytes(params.ipfsCID)) != keccak256(bytes("")),
            InvalidFeedConfig()
        );
        require(
            params.subscriptionDueTime > block.timestamp,
            InvalidFeedConfig()
        );
    }

    function _createFeed(
        CreateFeedParams calldata params,
        bytes32 dataSourceId
    ) internal {
        address feed = address(
            new Feed(
                IFeed.CreateFeedParams({
                    feedType: params.feedType,
                    accessControlManager: address(_accessControlManager),
                    owner: msg.sender,
                    frequency: params.frequency,
                    signaturesRequired: params.minSignaturesThreshold,
                    consumerPricePerSecondScaled: params
                        .consumerPricePerSecondScaled,
                    ipfsCID: params.ipfsCID,
                    dataSourceId: dataSourceId
                })
            )
        );

        _subscriptionRegistry.initFeedSubscription(
            feed,
            msg.sender,
            params.subscriptionDueTime,
            params.defaultConsumers
        );

        emit LogFeedCreated(
            feed,
            params.feedType,
            params.frequency,
            params.minSignaturesThreshold,
            params.ipfsCID
        );
    }
}
