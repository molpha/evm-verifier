// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {IAccessControlManager} from "../..//src/interfaces/IAccessControlManager.sol";

contract MockAccessControlManager is IAccessControlManager, ERC165 {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant FEEDS_MANAGER = keccak256("FEEDS_MANAGER");
    bytes32 public constant NODES_MANAGER = keccak256("NODES_MANAGER");
    bytes32 public constant PRICE_MANAGER = keccak256("PRICE_MANAGER");

    address public admin;
    address public feedsManager;
    address public nodesManager;
    address public priceManager;

    constructor(address _admin) {
        admin = _admin;
        feedsManager = _admin;
        nodesManager = _admin;
        priceManager = _admin;
    }

    function hasRole(bytes32 role, address account) external view override returns (bool) {
        if (role == ADMIN_ROLE) return account == admin;
        if (role == FEEDS_MANAGER) return account == feedsManager;
        if (role == NODES_MANAGER) return account == nodesManager;
        if (role == PRICE_MANAGER) return account == priceManager;
        return false;
    }

    function getRoleAdmin(bytes32) external pure override returns (bytes32) {
        return 0x00;
    }

    function grantRole(bytes32, address) external override {}
    function revokeRole(bytes32, address) external override {}
    function renounceRole(bytes32, address) external override {}

    function verifyProtocolAdmin(address account) external view override {
        if (account != admin) revert AccessControlUnauthorizedAccount(account, ADMIN_ROLE);
    }

    function verifyFeedsManager(address account) external view override {
        if (account != feedsManager) revert AccessControlUnauthorizedAccount(account, FEEDS_MANAGER);
    }

    function verifyNodesManager(address account) external view override {
        if (account != nodesManager) revert AccessControlUnauthorizedAccount(account, NODES_MANAGER);
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IAccessControlManager).interfaceId || super.supportsInterface(interfaceId);
    }
}
