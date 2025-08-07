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

    // bytes32 private constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version)");
    // keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes("Molpha Oracles")), keccak256(bytes("1"))));
    bytes32 private constant DOMAIN_SEPARATOR = 0x91af22df910089dce34bc41d0790bb4a1beee77dda588667c082bb964143739f;
    // keccak256("DataSource(uint8 type,string source,address owner,string name)");
    bytes32 private constant DATA_SOURCE_TYPEHASH = 0x2b67d03a9a9eb19ee3f5a924a5a495f9523224841dd674c995394bbe27c3bf40;

    IAccessControlManager public accessControlManager;

    mapping(bytes32 => DataSource) private _dataSources;

    modifier onlyFeedRegistryOrOwner(DataSource calldata dataSource) {
        if (dataSource.owner != msg.sender) {
            accessControlManager.verifyFeedRegistry(msg.sender);
        }
        _;
    }

    function initialize(address _accessControlManager) external override initializer {
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

        _verifySignature(dataSource, signature);

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

    function _generateDataSourceId(DataSource calldata dataSource) internal pure returns (bytes32 dataSourceId) {
        dataSourceId = keccak256(
            abi.encodePacked(
                dataSource.dataSourceType, 
                dataSource.source, 
                dataSource.owner, 
                dataSource.name    
            ));
    }

    function _verifySignature(DataSource calldata dataSource, bytes calldata signature) internal pure {
        bytes32 structHash = keccak256(
            abi.encode(
                DATA_SOURCE_TYPEHASH,
                dataSource.dataSourceType,
                keccak256(bytes(dataSource.source)),
                dataSource.owner,
                keccak256(bytes(dataSource.name))
            )
        );

        bytes32 digest = MessageHashUtils.toTypedDataHash(
            DOMAIN_SEPARATOR,
            structHash
        );
        address signer = digest.recover(signature);
        if (signer != dataSource.owner) {
            revert InvalidSignature();
        }
    }
}