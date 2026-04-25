// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DataSourceRegistry} from "../src/DataSourceRegistry.sol";
import {IDataSourceRegistry} from "../src/interfaces/IDataSourceRegistry.sol";
import {MockAccessControlManager} from "./mocks/MockAccessControlManager.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC165} from "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

contract DataSourceRegistryTest is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    DataSourceRegistry registry;
    MockAccessControlManager acl;

    address admin;
    address feedRegistry;
    address dataSourceOwner;
    address unauthorizedUser;

    uint256 privateKey;
    address signer;

    bytes32 private constant DOMAIN_SEPARATOR = 0x91af22df910089dce34bc41d0790bb4a1beee77dda588667c082bb964143739f;
    bytes32 private constant DATA_SOURCE_TYPEHASH = 0x2b67d03a9a9eb19ee3f5a924a5a495f9523224841dd674c995394bbe27c3bf40;

    function setUp() public {
        admin = address(this);
        feedRegistry = address(123);
        dataSourceOwner = address(456);
        unauthorizedUser = address(789);

        // Generate a key pair for signature testing
        (signer, privateKey) = makeAddrAndKey("signer");

        acl = new MockAccessControlManager(admin);
        acl.setFeedRegistry(feedRegistry);
        
        registry = new DataSourceRegistry();
        registry.initialize(address(acl));
    }

    function test_initialize() public {
        DataSourceRegistry newRegistry = new DataSourceRegistry();
        newRegistry.initialize(address(acl));
        
        // Verify that the access control manager is set correctly
        assertEq(address(newRegistry.accessControlManager()), address(acl));
    }

    function test_initialize_RevertIfAlreadyInitialized() public {
        vm.expectRevert("InvalidInitialization()");
        registry.initialize(address(acl));
    }

    function test_initialize_RevertIfInvalidAccessControlManager() public {
        DataSourceRegistry newRegistry = new DataSourceRegistry();
        vm.expectRevert(); // InterfaceNotSupported error
        newRegistry.initialize(address(0));
    }

    function test_createDataSource_ByOwner() public {
        IDataSourceRegistry.DataSource memory dataSource = IDataSourceRegistry.DataSource({
            owner: signer,
            dataSourceType: IDataSourceRegistry.DataSourceType.Public,
            source: "https://api.example.com",
            name: "Test Data Source"
        });

        bytes32 dataSourceId = registry.getDataSourceId(dataSource);
        bytes memory signature = _signDataSourceEIP712(dataSource, privateKey);

        vm.prank(signer);
        bytes32 createdId = registry.createDataSource(dataSource, signature);

        assertEq(createdId, dataSourceId);
        
        // Verify the data source was created correctly
        IDataSourceRegistry.DataSource memory retrieved = registry.getDataSource(dataSourceId);
        assertEq(retrieved.owner, dataSource.owner);
        assertEq(uint8(retrieved.dataSourceType), uint8(dataSource.dataSourceType));
        assertEq(retrieved.source, dataSource.source);
        assertEq(retrieved.name, dataSource.name);
    }

    function test_createDataSource_ByFeedRegistry() public {
        IDataSourceRegistry.DataSource memory dataSource = IDataSourceRegistry.DataSource({
            owner: signer,
            dataSourceType: IDataSourceRegistry.DataSourceType.Personal,
            source: "https://api.example.com",
            name: "Test Data Source"
        });

        bytes32 dataSourceId = registry.getDataSourceId(dataSource);
        bytes memory signature = _signDataSourceEIP712(dataSource, privateKey);

        vm.prank(feedRegistry);
        bytes32 createdId = registry.createDataSource(dataSource, signature);

        assertEq(createdId, dataSourceId);
        
        // Verify the data source was created correctly
        IDataSourceRegistry.DataSource memory retrieved = registry.getDataSource(dataSourceId);
        assertEq(retrieved.owner, dataSource.owner);
        assertEq(uint8(retrieved.dataSourceType), uint8(dataSource.dataSourceType));
        assertEq(retrieved.source, dataSource.source);
        assertEq(retrieved.name, dataSource.name);
    }

    function test_createDataSource_RevertIfUnauthorized() public {
        IDataSourceRegistry.DataSource memory dataSource = IDataSourceRegistry.DataSource({
            owner: signer,
            dataSourceType: IDataSourceRegistry.DataSourceType.Public,
            source: "https://api.example.com",
            name: "Test Data Source"
        });

        bytes memory signature = _signDataSourceEIP712(dataSource, privateKey);

        vm.prank(unauthorizedUser);
        vm.expectRevert("Not feed registry");
        registry.createDataSource(dataSource, signature);
    }

    function test_createDataSource_RevertIfInvalidSignature() public {
        IDataSourceRegistry.DataSource memory dataSource = IDataSourceRegistry.DataSource({
            owner: signer,
            dataSourceType: IDataSourceRegistry.DataSourceType.Public,
            source: "https://api.example.com",
            name: "Test Data Source"
        });

        bytes memory invalidSignature = "0x1234567890abcdef";

        vm.prank(signer);
        vm.expectRevert(); // ECDSAInvalidSignatureLength error
        registry.createDataSource(dataSource, invalidSignature);
    }

    function test_createDataSource_RevertIfEmptySignature() public {
        IDataSourceRegistry.DataSource memory dataSource = IDataSourceRegistry.DataSource({
            owner: signer,
            dataSourceType: IDataSourceRegistry.DataSourceType.Public,
            source: "https://api.example.com",
            name: "Test Data Source"
        });

        vm.prank(signer);
        vm.expectRevert(); // ECDSAInvalidSignatureLength error
        registry.createDataSource(dataSource, "");
    }

    function test_createDataSource_RevertIfAlreadyExists() public {
        IDataSourceRegistry.DataSource memory dataSource = IDataSourceRegistry.DataSource({
            owner: signer,
            dataSourceType: IDataSourceRegistry.DataSourceType.Public,
            source: "https://api.example.com",
            name: "Test Data Source"
        });

        bytes32 dataSourceId = registry.getDataSourceId(dataSource);
        bytes memory signature = _signDataSourceEIP712(dataSource, privateKey);

        // Create the data source first time
        vm.prank(signer);
        registry.createDataSource(dataSource, signature);

        // Try to create the same data source again
        vm.prank(signer);
        vm.expectRevert("DataSource exists");
        registry.createDataSource(dataSource, signature);
    }

    function test_getDataSource() public {
        IDataSourceRegistry.DataSource memory dataSource = IDataSourceRegistry.DataSource({
            owner: signer,
            dataSourceType: IDataSourceRegistry.DataSourceType.Public,
            source: "https://api.example.com",
            name: "Test Data Source"
        });

        bytes32 dataSourceId = registry.getDataSourceId(dataSource);
        bytes memory signature = _signDataSourceEIP712(dataSource, privateKey);

        vm.prank(signer);
        registry.createDataSource(dataSource, signature);

        IDataSourceRegistry.DataSource memory retrieved = registry.getDataSource(dataSourceId);
        assertEq(retrieved.owner, dataSource.owner);
        assertEq(uint8(retrieved.dataSourceType), uint8(dataSource.dataSourceType));
        assertEq(retrieved.source, dataSource.source);
        assertEq(retrieved.name, dataSource.name);
    }

    function test_getDataSource_RevertIfNotFound() public {
        bytes32 nonExistentId = keccak256("non-existent");
        vm.expectRevert("DataSource not found");
        registry.getDataSource(nonExistentId);
    }

    function test_getDataSourceId() public view {
        IDataSourceRegistry.DataSource memory dataSource = IDataSourceRegistry.DataSource({
            owner: signer,
            dataSourceType: IDataSourceRegistry.DataSourceType.Public,
            source: "https://api.example.com",
            name: "Test Data Source"
        });

        bytes32 expectedId = keccak256(abi.encodePacked(
            dataSource.dataSourceType,
            dataSource.source,
            dataSource.owner,
            dataSource.name
        ));

        bytes32 actualId = registry.getDataSourceId(dataSource);
        assertEq(actualId, expectedId);
    }

    function test_supportsInterface() public view {
        assertTrue(registry.supportsInterface(type(IDataSourceRegistry).interfaceId));
        assertTrue(registry.supportsInterface(type(IERC165).interfaceId));
        assertFalse(registry.supportsInterface(0x12345678));
    }

    function test_createDataSource_EmitsEvent() public {
        IDataSourceRegistry.DataSource memory dataSource = IDataSourceRegistry.DataSource({
            owner: signer,
            dataSourceType: IDataSourceRegistry.DataSourceType.Public,
            source: "https://api.example.com",
            name: "Test Data Source"
        });

        bytes32 dataSourceId = registry.getDataSourceId(dataSource);
        bytes memory signature = _signDataSourceEIP712(dataSource, privateKey);

        vm.prank(signer);
        vm.expectEmit(true, true, true, true);
        emit IDataSourceRegistry.DataSourceCreated(
            dataSourceId,
            dataSource.owner,
            dataSource.dataSourceType,
            dataSource.source,
            dataSource.name
        );
        registry.createDataSource(dataSource, signature);
    }

    function test_createDataSource_DifferentTypes() public {
        // Test Public type
        IDataSourceRegistry.DataSource memory publicDataSource = IDataSourceRegistry.DataSource({
            owner: signer,
            dataSourceType: IDataSourceRegistry.DataSourceType.Public,
            source: "https://api.example.com/public",
            name: "Public Data Source"
        });

        bytes32 publicId = registry.getDataSourceId(publicDataSource);
        bytes memory publicSignature = _signDataSourceEIP712(publicDataSource, privateKey);

        vm.prank(signer);
        registry.createDataSource(publicDataSource, publicSignature);

        // Test Personal type
        IDataSourceRegistry.DataSource memory personalDataSource = IDataSourceRegistry.DataSource({
            owner: signer,
            dataSourceType: IDataSourceRegistry.DataSourceType.Personal,
            source: "https://api.example.com/personal",
            name: "Personal Data Source"
        });

        bytes32 personalId = registry.getDataSourceId(personalDataSource);
        bytes memory personalSignature = _signDataSourceEIP712(personalDataSource, privateKey);

        vm.prank(signer);
        registry.createDataSource(personalDataSource, personalSignature);

        // Verify both were created
        IDataSourceRegistry.DataSource memory retrievedPublic = registry.getDataSource(publicId);
        IDataSourceRegistry.DataSource memory retrievedPersonal = registry.getDataSource(personalId);

        assertEq(uint8(retrievedPublic.dataSourceType), uint8(IDataSourceRegistry.DataSourceType.Public));
        assertEq(uint8(retrievedPersonal.dataSourceType), uint8(IDataSourceRegistry.DataSourceType.Personal));
    }

    function test_createDataSource_DifferentOwners() public {
        (address owner1, uint256 key1) = makeAddrAndKey("owner1");
        (address owner2, uint256 key2) = makeAddrAndKey("owner2");

        IDataSourceRegistry.DataSource memory dataSource1 = IDataSourceRegistry.DataSource({
            owner: owner1,
            dataSourceType: IDataSourceRegistry.DataSourceType.Public,
            source: "https://api.example.com/1",
            name: "Data Source 1"
        });

        IDataSourceRegistry.DataSource memory dataSource2 = IDataSourceRegistry.DataSource({
            owner: owner2,
            dataSourceType: IDataSourceRegistry.DataSourceType.Public,
            source: "https://api.example.com/2",
            name: "Data Source 2"
        });

        bytes32 id1 = registry.getDataSourceId(dataSource1);
        bytes32 id2 = registry.getDataSourceId(dataSource2);
        
        bytes memory signature1 = _signDataSourceEIP712(dataSource1, key1);
        bytes memory signature2 = _signDataSourceEIP712(dataSource2, key2);

        vm.prank(owner1);
        registry.createDataSource(dataSource1, signature1);

        vm.prank(owner2);
        registry.createDataSource(dataSource2, signature2);

        // Verify both were created with correct owners
        IDataSourceRegistry.DataSource memory retrieved1 = registry.getDataSource(id1);
        IDataSourceRegistry.DataSource memory retrieved2 = registry.getDataSource(id2);

        assertEq(retrieved1.owner, owner1);
        assertEq(retrieved2.owner, owner2);
    }

    function _signDataSourceEIP712(IDataSourceRegistry.DataSource memory dataSource, uint256 signerPrivateKey) internal pure returns (bytes memory) {
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
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }
} 