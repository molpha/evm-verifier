// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.4 <0.9.0;

import {IVerifier} from "@molpha/evm-verifier/interfaces/IVerifier.sol";
import {MolphaLib} from "@molpha/evm-verifier/consumer/MolphaLib.sol";

/// @notice Kind A + `Latest`: a two-sided bet settled by one signed `int256`.
/// @dev Shows the default shape — validate, guard, act. Payout is pull, not push, so a hostile
///      counterparty cannot brick settlement by rejecting a transfer.
contract SettleOnWord {
    using MolphaLib for IVerifier;
    using MolphaLib for MolphaLib.Latest;

    IVerifier public immutable VERIFIER;
    int256 public immutable STRIKE;
    address public immutable ABOVE;
    address public immutable BELOW;

    MolphaLib.Policy internal policy;
    MolphaLib.Latest internal latest;

    address public winner;
    mapping(address => uint256) public owed;

    error NotSettled();
    error NothingOwed();

    constructor(IVerifier verifier, bytes32 sourceId, uint32 minSignatures, uint64 maxAge, int256 strike, address below)
        payable {
        VERIFIER = verifier;
        STRIKE = strike;
        ABOVE = msg.sender;
        BELOW = below;
        // The threshold floor is the consumer's own requirement: `sourceId` commits the source
        // configuration, never the number of signatures behind a given attestation.
        policy = MolphaLib.Policy({sourceId: sourceId, minSignatures: minSignatures, maxAge: maxAge});
    }

    function settle(IVerifier.Attestation calldata att) external {
        VERIFIER.requireValid(att, policy);
        latest.acceptNewer(att.payload);

        address won = MolphaLib.asInt256(att.payload.value) >= STRIKE ? ABOVE : BELOW;
        winner = won;
        owed[won] = address(this).balance;
    }

    function withdraw() external {
        if (winner == address(0)) revert NotSettled();
        uint256 amount = owed[msg.sender];
        if (amount == 0) revert NothingOwed();
        owed[msg.sender] = 0;
        (bool sent,) = msg.sender.call{value: amount}("");
        require(sent, "transfer failed");
    }
}
