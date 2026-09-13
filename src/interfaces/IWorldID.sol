// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Minimal surface of the World ID router needed for on-chain verification.
/// @dev Reverts on an invalid proof; returns nothing on success.
interface IWorldID {
    function verifyProof(
        uint256 root,
        uint256 groupId,
        uint256 signalHash,
        uint256 nullifierHash,
        uint256 externalNullifierHash,
        uint256[8] calldata proof
    ) external view;
}
