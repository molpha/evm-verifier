// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;

import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";

contract AccessControlManager is AccessControl, IAccessControlManager, Initializable {
    bytes32 public constant override NODE_REGISTRY = keccak256("NODE_REGISTRY");
    bytes32 public constant override PRICE_MANAGER = keccak256("PRICE_MANAGER");
    bytes32 public constant override FEED_REGISTRY = keccak256("FEED_REGISTRY");
    bytes32 public constant override SUBSCRIPTION_REGISTRY = keccak256("SUBSCRIPTION_REGISTRY");

    function initialize(address _protocolAdmin) external override initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, _protocolAdmin);
    }

    /// @inheritdoc IAccessControlManager
    function verifyProtocolAdmin(address account) external view override {
        _checkRole(DEFAULT_ADMIN_ROLE, account);
    }

    /// @inheritdoc IAccessControlManager
    function verifyPriceManager(address account) external view override {
        _checkRole(PRICE_MANAGER, account);
    }

    /// @inheritdoc IAccessControlManager
    function verifyNodeRegistry(address account) external view override {
        _checkRole(NODE_REGISTRY, account);
    }

    /// @inheritdoc IAccessControlManager
    function verifyFeedRegistry(address account) external view override {
        _checkRole(FEED_REGISTRY, account);
    }

    /// @inheritdoc IAccessControlManager
    function verifySubscriptionRegistry(address account) external view override {
        _checkRole(SUBSCRIPTION_REGISTRY, account);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IAccessControlManager).interfaceId || super.supportsInterface(interfaceId);
    }
}
