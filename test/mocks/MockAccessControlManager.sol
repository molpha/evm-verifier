// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAccessControlManager} from "../..//src/interfaces/IAccessControlManager.sol";

contract MockAccessControlManager is IAccessControlManager {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant FEEDS_MANAGER = keccak256("FEEDS_MANAGER");
    bytes32 public constant NODES_MANAGER = keccak256("NODES_MANAGER");

    address public admin;
    address public feedsManager;
    address public nodesManager;

    constructor(address _admin) {
        admin = _admin;
        feedsManager = _admin;
        nodesManager = _admin;
    }

    function hasRole(bytes32 role, address account) external view override returns (bool) {
        if (role == ADMIN_ROLE) return account == admin;
        if (role == FEEDS_MANAGER) return account == feedsManager;
        if (role == NODES_MANAGER) return account == nodesManager;
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
}
