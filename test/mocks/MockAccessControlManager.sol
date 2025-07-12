// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAccessControlManager} from "../..//src/interfaces/IAccessControlManager.sol";

contract MockAccessControlManager is IAccessControlManager {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant FEED_MANAGER = keccak256("FEED_MANAGER");
    bytes32 public constant NODE_MANAGER = keccak256("NODE_MANAGER");
    bytes32 public constant PRICE_MANAGER = keccak256("PRICE_MANAGER");

    address public admin;
    address public feedManager;
    address public nodeManager;
    address public priceManager;

    constructor(address _admin) {
        admin = _admin;
        feedManager = _admin;
        nodeManager = _admin;
        priceManager = _admin;
    }

    function hasRole(bytes32 role, address account) external view override returns (bool) {
        if (role == ADMIN_ROLE) return account == admin;
        if (role == FEED_MANAGER) return account == feedManager;
        if (role == NODE_MANAGER) return account == nodeManager;
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

    function verifyFeedManager(address account) external view override {
        if (account != feedManager) revert AccessControlUnauthorizedAccount(account, FEED_MANAGER);
    }

    function verifyNodeManager(address account) external view override {
        if (account != nodeManager) revert AccessControlUnauthorizedAccount(account, NODE_MANAGER);
    }

    function verifyPriceManager(address account) external view override {
        if (account != priceManager) revert AccessControlUnauthorizedAccount(account, PRICE_MANAGER);
    }

    function setFeedManager(address account) external {
        feedManager = account;
    }

    function setNodeManager(address account) external {
        nodeManager = account;
    }

    function setProtocolAdmin(address account) external {
        admin = account;
    }

    function setPriceManager(address account) external {
        priceManager = account;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IAccessControlManager).interfaceId ||
               interfaceId == 0x01ffc9a7; // ERC165 interface ID
    }
}
