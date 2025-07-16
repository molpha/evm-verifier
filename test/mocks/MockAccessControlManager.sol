// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IAccessControlManager} from "../../src/interfaces/IAccessControlManager.sol";

contract MockAccessControlManager is IAccessControlManager {
    address public admin;
    address public feedManager;
    address public nodeManager;
    address public priceManager;
    address public feedRegistry;
    address public nodeRegistry;

    constructor(address _admin) {
        admin = _admin;
    }

    function initialize(address protocolAdmin) external {
        admin = protocolAdmin;
    }

    function setFeedManager(address _feedManager) external {
        feedManager = _feedManager;
    }

    function setNodeManager(address _nodeManager) external {
        nodeManager = _nodeManager;
    }

    function setPriceManager(address _priceManager) external {
        priceManager = _priceManager;
    }

    function setFeedRegistry(address _feedRegistry) external {
        feedRegistry = _feedRegistry;
    }

    function setNodeRegistry(address _nodeRegistry) external {
        nodeRegistry = _nodeRegistry;
    }

    // IAccessControlManager interface implementation
    function NODE_REGISTRY() external pure returns (bytes32) {
        return keccak256("NODE_REGISTRY");
    }

    function PRICE_MANAGER() external pure returns (bytes32) {
        return keccak256("PRICE_MANAGER");
    }

    function verifyProtocolAdmin(address account) external view {
        require(account == admin, "Not admin");
    }

    function verifyPriceManager(address account) external view {
        require(account == priceManager, "Not price manager");
    }

    function verifyNodeRegistry(address account) external view {
        require(account == nodeRegistry, "Not node registry");
    }

    // Helper methods for testing (not part of interface)
    function ADMIN_ROLE() external pure returns (bytes32) {
        return keccak256("ADMIN_ROLE");
    }

    function FEED_MANAGER() external pure returns (bytes32) {
        return keccak256("FEED_MANAGER");
    }

    function FEED_REGISTRY() external pure returns (bytes32) {
        return keccak256("FEED_REGISTRY");
    }

    function NODE_MANAGER() external pure returns (bytes32) {
        return keccak256("NODE_MANAGER");
    }

    function verifyFeedManager(address account) external view {
        require(account == feedManager, "Not feed manager");
    }

    function verifyFeedRegistry(address account) external view {
        require(account == feedRegistry, "Not feed registry");
    }

    function verifyNodeManager(address account) external view {
        require(account == nodeManager, "Not node manager");
    }

    // IAccessControl interface implementation (simplified)
    function hasRole(bytes32 role, address account) external view returns (bool) {
        if (role == keccak256("ADMIN_ROLE")) return account == admin;
        if (role == keccak256("FEED_MANAGER")) return account == feedManager;
        if (role == keccak256("NODE_MANAGER")) return account == nodeManager;
        if (role == keccak256("PRICE_MANAGER")) return account == priceManager;
        if (role == keccak256("FEED_REGISTRY")) return account == feedRegistry;
        if (role == keccak256("NODE_REGISTRY")) return account == nodeRegistry;
        return false;
    }

    function getRoleAdmin(bytes32) external pure returns (bytes32) {
        return keccak256("ADMIN_ROLE");
    }

    function grantRole(bytes32 role, address account) external {
        require(msg.sender == admin, "Not admin");
        // Simple implementation - in real contract would emit events
        if (role == keccak256("FEED_MANAGER")) feedManager = account;
        if (role == keccak256("NODE_MANAGER")) nodeManager = account;
        if (role == keccak256("PRICE_MANAGER")) priceManager = account;
        if (role == keccak256("FEED_REGISTRY")) feedRegistry = account;
        if (role == keccak256("NODE_REGISTRY")) nodeRegistry = account;
    }

    function revokeRole(bytes32, address) external {
        require(msg.sender == admin, "Not admin");
        // Simple implementation
    }

    function renounceRole(bytes32, address) external {
        // Simple implementation
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IAccessControlManager).interfaceId || interfaceId == 0x01ffc9a7; // ERC165
    }
}
