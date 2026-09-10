// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";

import {LatestStore} from "../../examples/LatestStore.sol";
import {IVerifier} from "@molpha/evm-verifier/interfaces/IVerifier.sol";
import {MolphaLib} from "@molpha/evm-verifier/consumer/MolphaLib.sol";
import {MolphaTestSigner} from "@molpha/evm-verifier/test-utils/MolphaTestSigner.sol";

contract LatestStoreTest is Test {
    bytes32 internal constant SOURCE_A = keccak256("MOLPHA_SOURCE_A");
    bytes32 internal constant SOURCE_B = keccak256("MOLPHA_SOURCE_B");
    bytes32 internal constant UNLISTED = keccak256("MOLPHA_SOURCE_UNLISTED");
    uint8 internal constant MIN_SIGS = 5;

    MolphaTestSigner internal signer;
    LatestStore internal store;

    function setUp() public {
        vm.warp(1_700_000_000);
        signer = new MolphaTestSigner(2);
        signer.registerNodes(8);

        bytes32[] memory sources = new bytes32[](2);
        sources[0] = SOURCE_A;
        sources[1] = SOURCE_B;
        store = new LatestStore(IVerifier(address(signer.verifier())), sources, MIN_SIGS, MolphaLib.NO_MAX_AGE);
    }

    function _att(bytes32 source, uint256 value, uint64 ts) internal view returns (IVerifier.Attestation memory) {
        return signer.attest(source, bytes32(value), MIN_SIGS, ts);
    }

    function test_anyoneMaySubmit() public {
        vm.prank(address(0xCAFE));
        store.submit(_att(SOURCE_A, 42, uint64(block.timestamp)));
        assertEq(store.value(SOURCE_A), bytes32(uint256(42)));
    }

    function test_unlistedSourceIsRejected() public {
        IVerifier.Attestation memory att = _att(UNLISTED, 1, uint64(block.timestamp));
        vm.expectRevert(abi.encodeWithSelector(LatestStore.SourceNotAllowed.selector, UNLISTED));
        store.submit(att);
    }

    /// @dev The reason `LatestStore` keys its guard by source: two feeds must advance
    ///      independently rather than blocking each other.
    function test_twoSourcesAdvanceIndependently() public {
        uint64 t0 = uint64(block.timestamp);
        store.submit(_att(SOURCE_A, 1, t0 + 500));
        store.submit(_att(SOURCE_B, 2, t0 + 100));

        assertEq(store.lastTimestamp(SOURCE_A), t0 + 500);
        assertEq(store.lastTimestamp(SOURCE_B), t0 + 100);
        assertEq(store.value(SOURCE_A), bytes32(uint256(1)));
        assertEq(store.value(SOURCE_B), bytes32(uint256(2)));
    }

    function test_outOfOrderUpdateIsRejectedPerSourceOnly() public {
        uint64 t0 = uint64(block.timestamp);
        store.submit(_att(SOURCE_A, 1, t0 + 500));

        IVerifier.Attestation memory stale = _att(SOURCE_A, 2, t0 + 400);
        vm.expectPartialRevert(MolphaLib.NotNewer.selector);
        store.submit(stale);

        // The other source is unaffected by A's rejection.
        store.submit(_att(SOURCE_B, 3, t0 + 400));
        assertEq(store.value(SOURCE_B), bytes32(uint256(3)));
        assertEq(store.value(SOURCE_A), bytes32(uint256(1)));
    }

    function test_thresholdFloorAppliesToEverySource() public {
        IVerifier.Attestation memory weak =
            signer.attest(SOURCE_A, bytes32(uint256(1)), MIN_SIGS - 1, uint64(block.timestamp));
        vm.expectPartialRevert(MolphaLib.ThresholdBelowPolicy.selector);
        store.submit(weak);
    }
}
