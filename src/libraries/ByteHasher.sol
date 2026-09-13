// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library ByteHasher {
    /// @dev Hashes bytes into a field element of the BN254 scalar field, which is
    ///      what World ID's circuits expect. Shifting right by 8 bits keeps the
    ///      result below the field modulus.
    function hashToField(bytes memory value) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(value))) >> 8;
    }
}
