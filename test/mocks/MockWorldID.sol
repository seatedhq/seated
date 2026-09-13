// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IWorldID} from "../../src/interfaces/IWorldID.sol";

/// @dev Test double for the World ID router. `verifyProof` is `view` on the real
///      router, so this mock cannot record calls — tests assert on the signal by
///      recomputing the expected hash and using `vm.expectCall`.
///
///      Signal checking is opt-in via `setExpectedSignal` so the default behaviour
///      stays permissive for tests that don't care about the signal. Once armed,
///      `verifyProof` reverts unless the submitted signal hash matches.
contract MockWorldID is IWorldID {
    error MockWorldIdRejected();
    error MockWorldIdSignalMismatch();

    bool public shouldReject;
    bool public signalCheckEnabled;
    uint256 public expectedSignalHash;

    function setShouldReject(bool value) external {
        shouldReject = value;
    }

    /// @dev Arms strict signal checking: subsequent `verifyProof` calls revert
    ///      unless `signalHash` matches exactly.
    function setExpectedSignal(uint256 signalHash) external {
        signalCheckEnabled = true;
        expectedSignalHash = signalHash;
    }

    function verifyProof(uint256, uint256, uint256 signalHash, uint256, uint256, uint256[8] calldata) external view {
        if (shouldReject) revert MockWorldIdRejected();
        if (signalCheckEnabled && signalHash != expectedSignalHash) revert MockWorldIdSignalMismatch();
    }
}
