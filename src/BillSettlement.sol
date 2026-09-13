// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {VenueRegistry} from "./VenueRegistry.sol";

/// @title BillSettlement
/// @notice Records a USDC bill payment as a tier-2 attendance proof.
/// @dev Deliberately not an escrow. Funds move diner -> venue owner in one call;
///      the contract never holds a balance.
contract BillSettlement {
    using SafeERC20 for IERC20;

    struct SettlementProof {
        address venue;
        address diner;
        uint256 amount;
        uint64 settledAt;
    }

    VenueRegistry public immutable registry;
    IERC20 public immutable usdc;

    /// @dev Nonce ensuring proofId uniqueness for identical payments in one block.
    uint256 public settlementCount;

    mapping(bytes32 => SettlementProof) private _proofs;

    event BillSettled(
        bytes32 indexed proofId, address indexed venue, address indexed diner, uint256 amount, uint64 settledAt
    );

    error VenueNotActive();
    error ZeroAmount();

    constructor(VenueRegistry registry_, IERC20 usdc_) {
        registry = registry_;
        usdc = usdc_;
    }

    /// @notice Pay a venue's bill in USDC and receive a tier-2 proof.
    function settle(address venue, uint256 amount) external returns (bytes32 proofId) {
        if (!registry.isActive(venue)) revert VenueNotActive();
        if (amount == 0) revert ZeroAmount();

        usdc.safeTransferFrom(msg.sender, registry.ownerOf(venue), amount);

        proofId = keccak256(abi.encode(venue, msg.sender, amount, block.timestamp, settlementCount));
        unchecked {
            settlementCount += 1;
        }

        _proofs[proofId] =
            SettlementProof({venue: venue, diner: msg.sender, amount: amount, settledAt: uint64(block.timestamp)});

        emit BillSettled(proofId, venue, msg.sender, amount, uint64(block.timestamp));
    }

    function proofOf(bytes32 proofId) external view returns (SettlementProof memory) {
        return _proofs[proofId];
    }
}
