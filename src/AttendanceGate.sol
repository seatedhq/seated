// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {VenueRegistry} from "./VenueRegistry.sol";

/// @title AttendanceGate
/// @notice Turns a venue-signed EIP-712 check-in voucher into a single-use, capped
///         attendance proof that ReviewRegistry will accept as tier 1.
contract AttendanceGate is EIP712 {
    struct CheckIn {
        address venue;
        address diner;
        uint64 seatedAt;
        uint64 expiry;
        bytes32 salt;
    }

    struct AttendanceProof {
        address venue;
        address diner;
        uint64 redeemedAt;
    }

    bytes32 public constant CHECKIN_TYPEHASH =
        keccak256("CheckIn(address venue,address diner,uint64 seatedAt,uint64 expiry,bytes32 salt)");

    VenueRegistry public immutable registry;

    mapping(bytes32 => AttendanceProof) private _proofs;
    /// @dev nullifier => redeemed. The nullifier doubles as the proofId.
    mapping(bytes32 => bool) public nullifierUsed;
    /// @dev venue => UTC day index => covers redeemed that day.
    mapping(address => mapping(uint256 => uint32)) public coversOnDay;

    event CheckInRedeemed(
        bytes32 indexed proofId, address indexed venue, address indexed diner, uint64 seatedAt, uint64 redeemedAt
    );

    error BadVenueSignature();
    error VoucherExpired();
    error VoucherUsed();
    error CapacityExceeded();
    error VenueNotActive();
    error NotVoucherDiner();
    error InvalidSeatedAt();

    constructor(VenueRegistry registry_) EIP712("Seated", "1") {
        registry = registry_;
    }

    /// @notice EIP-712 digest the venue's signing key must sign. Exposed so the
    ///         frontend builds the QR payload against the same hash the gate checks.
    function hashCheckIn(CheckIn calldata checkIn) external view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    CHECKIN_TYPEHASH, checkIn.venue, checkIn.diner, checkIn.seatedAt, checkIn.expiry, checkIn.salt
                )
            )
        );
    }

    /// @notice Redeem a check-in voucher for an attendance proof.
    /// @dev Check order is deliberate and demo-visible: signature, expiry, seatedAt, replay, capacity.
    function redeem(CheckIn calldata checkIn, bytes calldata signature) external returns (bytes32 proofId) {
        if (msg.sender != checkIn.diner) revert NotVoucherDiner();
        if (!registry.isActive(checkIn.venue)) revert VenueNotActive();

        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    CHECKIN_TYPEHASH, checkIn.venue, checkIn.diner, checkIn.seatedAt, checkIn.expiry, checkIn.salt
                )
            )
        );
        (address signer, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, signature);
        if (err != ECDSA.RecoverError.NoError || signer != registry.signingKeyOf(checkIn.venue)) {
            revert BadVenueSignature();
        }

        if (block.timestamp >= checkIn.expiry) revert VoucherExpired();
        if (checkIn.seatedAt > block.timestamp) revert InvalidSeatedAt();

        bytes32 nullifier = keccak256(abi.encode(checkIn.venue, checkIn.diner, checkIn.salt));
        if (nullifierUsed[nullifier]) revert VoucherUsed();

        // Capacity buckets are UTC days, not restaurant-local days. Good enough:
        // the commitment is an order-of-magnitude honesty check, not an audit.
        uint256 day = block.timestamp / 1 days;
        uint32 used = coversOnDay[checkIn.venue][day];
        if (used >= registry.maxCoversPerDayOf(checkIn.venue)) revert CapacityExceeded();

        nullifierUsed[nullifier] = true;
        coversOnDay[checkIn.venue][day] = used + 1;

        proofId = nullifier;
        _proofs[proofId] =
            AttendanceProof({venue: checkIn.venue, diner: checkIn.diner, redeemedAt: uint64(block.timestamp)});

        emit CheckInRedeemed(proofId, checkIn.venue, checkIn.diner, checkIn.seatedAt, uint64(block.timestamp));
    }

    function proofOf(bytes32 proofId) external view returns (AttendanceProof memory) {
        return _proofs[proofId];
    }
}
