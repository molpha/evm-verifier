// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";

import {IVerifier} from "../../src/interfaces/IVerifier.sol";
import {MolphaLib} from "../../src/consumer/MolphaLib.sol";
import {MolphaLibHarness} from "./MolphaLibHarness.sol";

contract MolphaLibReplayTest is Test {
    bytes32 internal constant SOURCE = keccak256("MOLPHA_TEST_SOURCE");
    bytes32 internal constant OTHER_SOURCE = keccak256("MOLPHA_OTHER_SOURCE");

    MolphaLibHarness internal harness;

    function setUp() public {
        harness = new MolphaLibHarness();
    }

    function _payload(bytes32 sourceId, uint32 registryVersion, uint64 ts)
        internal
        pure
        returns (IVerifier.AttestationPayload memory)
    {
        return IVerifier.AttestationPayload({
            value: bytes32(uint256(1)),
            sourceId: sourceId,
            registryVersion: registryVersion,
            signaturesRequired: 5,
            canonicalTimestamp: ts
        });
    }

    // ---------------- Latest.acceptNewer ----------------

    function test_acceptsFirstUpdateFromZero() public {
        harness.acceptNewer(_payload(SOURCE, 1, 1_700_000_000));
        assertEq(harness.lastTimestamp(), 1_700_000_000);
    }

    function test_acceptsStrictlyIncreasingTimestamps() public {
        harness.acceptNewer(_payload(SOURCE, 1, 100));
        harness.acceptNewer(_payload(SOURCE, 1, 101));
        harness.acceptNewer(_payload(SOURCE, 1, 5_000));
        assertEq(harness.lastTimestamp(), 5_000);
    }

    function test_equalTimestampReverts() public {
        harness.acceptNewer(_payload(SOURCE, 1, 100));
        vm.expectRevert(abi.encodeWithSelector(MolphaLib.NotNewer.selector, uint64(100), uint64(100)));
        harness.acceptNewer(_payload(SOURCE, 1, 100));
    }

    function test_olderTimestampReverts() public {
        harness.acceptNewer(_payload(SOURCE, 1, 100));
        vm.expectRevert(abi.encodeWithSelector(MolphaLib.NotNewer.selector, uint64(100), uint64(99)));
        harness.acceptNewer(_payload(SOURCE, 1, 99));
    }

    function test_stateIsUnchangedAfterARejectedUpdate() public {
        harness.acceptNewer(_payload(SOURCE, 1, 100));
        try harness.acceptNewer(_payload(SOURCE, 1, 50)) {
            revert("should have reverted");
        } catch {}
        assertEq(harness.lastTimestamp(), 100);
    }

    function test_zeroTimestampIsNeverAcceptedFromAFreshGuard() public {
        vm.expectRevert(abi.encodeWithSelector(MolphaLib.NotNewer.selector, uint64(0), uint64(0)));
        harness.acceptNewer(_payload(SOURCE, 1, 0));
    }

    /// @dev The documented footgun: one `Latest` shared across two sources makes them fight.
    ///      This is why `LatestStore` keys its guard by `sourceId`.
    function test_oneLatestSharedAcrossTwoSourcesRejectsTheSecondSource() public {
        harness.acceptNewer(_payload(SOURCE, 1, 500));
        vm.expectRevert(abi.encodeWithSelector(MolphaLib.NotNewer.selector, uint64(500), uint64(400)));
        harness.acceptNewer(_payload(OTHER_SOURCE, 1, 400));

        // Per-source guards do not interfere.
        harness.acceptNewerFor(SOURCE, _payload(SOURCE, 1, 500));
        harness.acceptNewerFor(OTHER_SOURCE, _payload(OTHER_SOURCE, 1, 400));
        assertEq(harness.lastTimestampFor(SOURCE), 500);
        assertEq(harness.lastTimestampFor(OTHER_SOURCE), 400);
    }

    // ---------------- Consumed.consumeOnce ----------------

    function test_consumesEachAttestationOnce() public {
        harness.consumeOnce(_payload(SOURCE, 1, 100));
        vm.expectRevert(
            abi.encodeWithSelector(MolphaLib.AlreadyConsumed.selector, keccak256(abi.encodePacked(SOURCE, uint64(100))))
        );
        harness.consumeOnce(_payload(SOURCE, 1, 100));
    }

    function test_differentTimestampIsANewUpdate() public {
        harness.consumeOnce(_payload(SOURCE, 1, 100));
        harness.consumeOnce(_payload(SOURCE, 1, 101));
    }

    function test_differentSourceIsANewUpdate() public {
        harness.consumeOnce(_payload(SOURCE, 1, 100));
        harness.consumeOnce(_payload(OTHER_SOURCE, 1, 100));
    }

    function test_outOfOrderTimestampsAreBothAccepted() public {
        harness.consumeOnce(_payload(SOURCE, 1, 500));
        harness.consumeOnce(_payload(SOURCE, 1, 100));
    }

    // ---------------- the registryVersion exclusion ----------------

    /// @dev During the registry grace window the same observation can be attested under two
    ///      consecutive versions. Both are ONE logical update; including `registryVersion` in the
    ///      key would let the second replay the first.
    function test_sameSourceAndTimestampUnderTwoRegistryVersionsIsOneUpdate() public {
        assertEq(
            harness.replayKey(_payload(SOURCE, 11, 1_700_000_000)),
            harness.replayKey(_payload(SOURCE, 12, 1_700_000_000)),
            "registryVersion must not affect the key"
        );

        harness.consumeOnce(_payload(SOURCE, 11, 1_700_000_000));
        vm.expectRevert(
            abi.encodeWithSelector(
                MolphaLib.AlreadyConsumed.selector, keccak256(abi.encodePacked(SOURCE, uint64(1_700_000_000)))
            )
        );
        harness.consumeOnce(_payload(SOURCE, 12, 1_700_000_000));
    }

    function testFuzz_registryVersionNeverAffectsTheReplayKey(bytes32 sourceId, uint64 ts, uint32 v1, uint32 v2)
        public
        view
    {
        assertEq(harness.replayKey(_payload(sourceId, v1, ts)), harness.replayKey(_payload(sourceId, v2, ts)));
    }

    function testFuzz_replayKeyIsInjectiveOverSourceAndTimestamp(
        bytes32 sourceA,
        uint64 tsA,
        bytes32 sourceB,
        uint64 tsB
    ) public view {
        vm.assume(sourceA != sourceB || tsA != tsB);
        assertTrue(harness.replayKey(_payload(sourceA, 1, tsA)) != harness.replayKey(_payload(sourceB, 1, tsB)));
    }

    function testFuzz_replayKeyIgnoresValueAndThreshold(bytes32 value, uint8 signaturesRequired) public view {
        IVerifier.AttestationPayload memory a = _payload(SOURCE, 1, 100);
        IVerifier.AttestationPayload memory b = _payload(SOURCE, 1, 100);
        b.value = value;
        b.signaturesRequired = uint8(signaturesRequired);
        assertEq(harness.replayKey(a), harness.replayKey(b));
    }
}
