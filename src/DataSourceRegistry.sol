// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.29;
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";

import {IAccessControlManager} from "./interfaces/IAccessControlManager.sol";
import {IDataSourceRegistry} from "./interfaces/IDataSourceRegistry.sol";
import {ERC165Checker} from "./libs/ERC165Checker.sol";

contract DataSourceRegistry is IDataSourceRegistry, Initializable, ERC165 {
    using ECDSA for bytes32;
    using ERC165Checker for address;
    using MessageHashUtils for bytes32;

    IAccessControlManager public accessControlManager;

    mapping(bytes32 => DataSource) private _dataSources;

    modifier onlyFeedRegistryOrOwner(DataSource calldata dataSource) {
        if (dataSource.owner != msg.sender) {
            accessControlManager.verifyFeedRegistry(msg.sender);
        }
        _;
    }

    function initialize(address _accessControlManager) external initializer {
        _accessControlManager.shouldSupport(type(IAccessControlManager).interfaceId);
        accessControlManager = IAccessControlManager(_accessControlManager);
    }

    function createDataSource(DataSource calldata dataSource, bytes calldata signature)
        external
        onlyFeedRegistryOrOwner(dataSource)
        returns (bytes32)
    {
        bytes32 dataSourceId = _generateDataSourceId(dataSource);
        if (_dataSources[dataSourceId].owner != address(0)) {
            revert DataSourceAlreadyExists(dataSourceId);
        }

        _verifyDataSourceSignature(dataSourceId, dataSource.owner, signature);

        _dataSources[dataSourceId] = dataSource;
        emit DataSourceCreated(dataSourceId, dataSource.owner, dataSource.dataSourceType, dataSource.source, dataSource.name);

        return dataSourceId;
    }
    
    function getDataSource(bytes32 dataSourceId) external view returns (DataSource memory) {
        if (_dataSources[dataSourceId].owner == address(0)) {
            revert DataSourceNotFound(dataSourceId);
        }
        return _dataSources[dataSourceId];
    }

    function getDataSourceId(DataSource calldata dataSource) external pure returns (bytes32 dataSourceId) {
        dataSourceId = _generateDataSourceId(dataSource);
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IDataSourceRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    function _generateDataSourceId(DataSource calldata dataSource) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(dataSource.dataSourceType, dataSource.source, dataSource.owner, dataSource.name));
    }

    function _verifyDataSourceSignature(bytes32 dataSourceId, address owner, bytes calldata signature) internal pure {
        require(signature.length > 0, InvalidSignature());

        bytes32 ethSignedMessageHash = dataSourceId.toEthSignedMessageHash();
        address signer = ethSignedMessageHash.recover(signature);
        if (signer != owner) {
            revert InvalidSignature();
        }
    }
}
