// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";

import {SettleOnWord} from "../../examples/SettleOnWord.sol";
import {IVerifier} from "@molpha/evm-verifier/interfaces/IVerifier.sol";
import {MolphaLib} from "@molpha/evm-verifier/consumer/MolphaLib.sol";
import {MolphaTestSigner} from "@molpha/evm-verifier/test-utils/MolphaTestSigner.sol";
import {VerifyCodes} from "@molpha/evm-verifier/libs/VerifyCodes.sol";

contract SettleOnWordTest is Test {
    bytes32 internal constant SOURCE = keccak256("MOLPHA_PRICE_SOURCE");
    bytes32 internal constant OTHER = keccak256("MOLPHA_OTHER_SOURCE");
    uint32 internal constant MIN_SIGS = 5;
    int256 internal constant STRIKE = 1_000;

    MolphaTestSigner internal signer;
    IVerifier internal v;
    SettleOnWord internal bet;
    address internal below = address(0xB0B);

    function setUp() public {
        vm.warp(1_700_000_000);
        signer = new MolphaTestSigner(2);
        signer.registerNodes(8);
        v = IVerifier(address(signer.verifier()));
        bet = new SettleOnWord{value: 10 ether}(v, SOURCE, MIN_SIGS, MolphaLib.NO_MAX_AGE, STRIKE, below);
    }

    function _att(int256 price, uint32 sigs, bytes32 source, uint64 ts)
        internal
        view
        returns (IVerifier.Attestation memory)
    {
        return signer.attest(source, bytes32(uint256(price)), sigs, ts);
    }

    function test_settlesAboveStrikeToTheDeployer() public {
        bet.settle(_att(STRIKE + 1, MIN_SIGS, SOURCE, uint64(block.timestamp)));
        assertEq(bet.winner(), address(this));
        assertEq(bet.owed(address(this)), 10 ether);
    }

    function test_settlesBelowStrikeToTheCounterparty() public {
        bet.settle(_att(STRIKE - 1, MIN_SIGS, SOURCE, uint64(block.timestamp)));
        assertEq(bet.winner(), below);
    }

    function test_negativeValueDecodesAsSigned() public {
        bet.settle(_att(-42, MIN_SIGS, SOURCE, uint64(block.timestamp)));
        assertEq(bet.winner(), below, "-42 is below the strike");
    }

    function test_winnerPullsTheBalance() public {
        bet.settle(_att(STRIKE + 1, MIN_SIGS, SOURCE, uint64(block.timestamp)));
        uint256 before = address(this).balance;
        bet.withdraw();
        assertEq(address(this).balance - before, 10 ether);
        assertEq(bet.owed(address(this)), 0);
    }

    function test_wrongSourceIsRejected() public {
        IVerifier.Attestation memory att = _att(STRIKE + 1, MIN_SIGS, OTHER, uint64(block.timestamp));
        vm.expectPartialRevert(MolphaLib.WrongSource.selector);
        bet.settle(att);
    }

    function test_thresholdBelowTheConsumerFloorIsRejected() public {
        IVerifier.Attestation memory att = _att(STRIKE + 1, MIN_SIGS - 1, SOURCE, uint64(block.timestamp));
        vm.expectPartialRevert(MolphaLib.ThresholdBelowPolicy.selector);
        bet.settle(att);
    }

    function test_tamperedValueIsRejectedBySignature() public {
        IVerifier.Attestation memory att = _att(STRIKE + 1, MIN_SIGS, SOURCE, uint64(block.timestamp));
        att.payload.value = bytes32(uint256(int256(STRIKE - 1)));
        vm.expectRevert(abi.encodeWithSelector(MolphaLib.VerifyFailed.selector, VerifyCodes.R_BAD_SIGNATURE));
        bet.settle(att);
    }

    function test_replayingTheSameAttestationIsRejected() public {
        IVerifier.Attestation memory att = _att(STRIKE + 1, MIN_SIGS, SOURCE, uint64(block.timestamp));
        bet.settle(att);
        vm.expectPartialRevert(MolphaLib.NotNewer.selector);
        bet.settle(att);
    }

    function test_olderAttestationIsRejectedAfterANewerOne() public {
        uint64 t0 = uint64(block.timestamp);
        vm.warp(t0 + 100);
        bet.settle(_att(STRIKE + 1, MIN_SIGS, SOURCE, t0 + 100));
        IVerifier.Attestation memory older = _att(STRIKE + 1, MIN_SIGS, SOURCE, t0);
        vm.expectPartialRevert(MolphaLib.NotNewer.selector);
        bet.settle(older);
    }

    function test_staleAttestationIsRejectedUnderAMaxAgePolicy() public {
        SettleOnWord fresh = new SettleOnWord{value: 1 ether}(v, SOURCE, MIN_SIGS, 3600, STRIKE, below);
        IVerifier.Attestation memory att = _att(STRIKE + 1, MIN_SIGS, SOURCE, uint64(block.timestamp));
        vm.warp(block.timestamp + 3601);
        vm.expectRevert(abi.encodeWithSelector(MolphaLib.VerifyFailed.selector, VerifyCodes.R_STALE));
        fresh.settle(att);
    }

    function test_withdrawBeforeSettlementReverts() public {
        vm.expectRevert(SettleOnWord.NotSettled.selector);
        bet.withdraw();
    }

    function test_loserIsOwedNothing() public {
        bet.settle(_att(STRIKE + 1, MIN_SIGS, SOURCE, uint64(block.timestamp)));
        vm.prank(below);
        vm.expectRevert(SettleOnWord.NothingOwed.selector);
        bet.withdraw();
    }

    function test_withdrawingTwiceIsRejected() public {
        bet.settle(_att(STRIKE + 1, MIN_SIGS, SOURCE, uint64(block.timestamp)));
        bet.withdraw();
        vm.expectRevert(SettleOnWord.NothingOwed.selector);
        bet.withdraw();
    }

    /// @dev Why the example uses pull payment: a winner that rejects ETH strands only its own
    ///      funds instead of bricking `settle` for everyone.
    function test_aWinnerThatRejectsEthCannotBlockSettlement() public {
        RejectsEth hostile = new RejectsEth();
        SettleOnWord fresh =
            new SettleOnWord{value: 1 ether}(v, SOURCE, MIN_SIGS, MolphaLib.NO_MAX_AGE, STRIKE, address(hostile));

        // Settlement succeeds even though the winner cannot receive ETH.
        fresh.settle(_att(STRIKE - 1, MIN_SIGS, SOURCE, uint64(block.timestamp)));
        assertEq(fresh.winner(), address(hostile));

        vm.prank(address(hostile));
        vm.expectRevert(bytes("transfer failed"));
        fresh.withdraw();
    }

    receive() external payable {}
}

contract RejectsEth {
    receive() external payable {
        revert("no thanks");
    }
}
