// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.4 <0.9.0;

import {IVerifier} from "@molpha/evm-verifier/interfaces/IVerifier.sol";
import {MolphaLib} from "@molpha/evm-verifier/consumer/MolphaLib.sol";

/// @notice Kind B + `Consumed`: a multi-field result carried as unsigned calldata.
/// @dev The signed `value` is `keccak256(encodedFields)`. `MolphaLib` owns only that hash binding;
///      the tuple layout is the consumer's, lifted verbatim from the source's schema.
///      `Consumed` accepts updates in any order at the cost of unbounded storage growth — use
///      `Latest` unless out-of-order acceptance is genuinely required.
contract StructuredPayload {
    using MolphaLib for IVerifier;
    using MolphaLib for MolphaLib.Consumed;

    IVerifier public immutable VERIFIER;

    MolphaLib.Policy internal policy;
    MolphaLib.Consumed internal consumed;

    struct Reading {
        uint256 amount;
        bytes32 label;
        string note;
    }

    Reading[] public readings;

    constructor(IVerifier verifier, bytes32 sourceId, uint32 minSignatures, uint64 maxAge) {
        VERIFIER = verifier;
        policy = MolphaLib.Policy({sourceId: sourceId, minSignatures: minSignatures, maxAge: maxAge});
    }

    /// @param encodedFields `abi.encode(uint256, bytes32, string)` per this source's schema.
    ///        Unsigned: its only guarantee is that it hashes to the signed `value`, which
    ///        `requireValid` checks before the signature is ever verified.
    function ingest(IVerifier.Attestation calldata att, bytes calldata encodedFields) external {
        VERIFIER.requireValid(att, policy, encodedFields);
        consumed.consumeOnce(att.payload);

        (uint256 amount, bytes32 label, string memory note) = abi.decode(encodedFields, (uint256, bytes32, string));
        readings.push(Reading({amount: amount, label: label, note: note}));
    }

    function readingCount() external view returns (uint256) {
        return readings.length;
    }
}
