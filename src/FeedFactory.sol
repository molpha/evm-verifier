// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.29;

import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {TransparentUpgradeableProxy} from
    "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {IFeed} from "./interfaces/IFeed.sol";
import {IFeedFactory} from "./interfaces/IFeedFactory.sol";
import {ERC165Checker} from "./libs/ERC165Checker.sol";


contract FeedFactory is IFeedFactory, ERC165 {
    using ERC165Checker for address;

    address internal _aggregatorImpl;

    IAccessControlManager internal immutable _accessControlManager;
    address internal immutable _proxyAdmin;

    modifier onlyProtocolAdmin() {
        _accessControlManager.verifyProtocolAdmin(msg.sender);
        _;
    }

    constructor(IAccessControlManager accessControlManager, address proxyAdmin) {
        address(accessControlManager).shouldSupport(type(IAccessControlManager).interfaceId);
        if(keccak256(bytes(ProxyAdmin(proxyAdmin).UPGRADE_INTERFACE_VERSION())) != keccak256(bytes("5.0.0"))) {
            revert("Wrong admin");
        }
        _accessControlManager = accessControlManager;
        _proxyAdmin = proxyAdmin;
    }

    // VK Notes: maybe remove this fn and use setAggregatorImpl?
    function initialize(
        address impl
    ) external {
        if(_aggregatorImpl != address(0)) {
            revert("Already initialized");
        }
        impl.shouldSupport(type(IFeed).interfaceId);

        _aggregatorImpl = impl;
    }

    /// @inheritdoc IFeedFactory
    function build() external override returns (address aggregator) {
        aggregator = address(new TransparentUpgradeableProxy(_aggregatorImpl, _proxyAdmin, new bytes(0)));
    }

    /// @inheritdoc IFeedFactory
    function setAggregatorImpl(address impl) external override onlyProtocolAdmin {
        impl.shouldSupport(type(IFeed).interfaceId);
        _aggregatorImpl = impl;
        emit LogFeedImplUpdated(impl);
    }


    /// @inheritdoc IFeedFactory
    function getAggregatorImpl() external view returns (address) {
        return _aggregatorImpl;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IFeedFactory).interfaceId || super.supportsInterface(interfaceId);
    }
}
