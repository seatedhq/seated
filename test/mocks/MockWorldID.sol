// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IWorldID} from "../../src/interfaces/IWorldID.sol";

/// @dev Test double for the World ID router. `verifyProof` is `view` on the real
///      router, so this mock cannot record calls — tests assert on the signal by
///      recomputing the expected hash and using `vm.expectCall`.
contract MockWorldID is IWorldID {
    error MockWorldIdRejected();

    bool public shouldReject;

    function setShouldReject(bool value) external {
        shouldReject = value;
    }

    function verifyProof(uint256, uint256, uint256, uint256, uint256, uint256[8] calldata) external view {
        if (shouldReject) revert MockWorldIdRejected();
    }
}
