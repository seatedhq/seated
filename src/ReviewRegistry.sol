// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {VenueRegistry} from "./VenueRegistry.sol";
import {AttendanceGate} from "./AttendanceGate.sol";
import {BillSettlement} from "./BillSettlement.sol";
import {IWorldID} from "./interfaces/IWorldID.sol";
import {ByteHasher} from "./libraries/ByteHasher.sol";

/// @title ReviewRegistry
/// @notice Reviews, each bound to a proof that the reviewer was actually there.
/// @dev Extends EIP712 for the venue-reply signature added in Task 6.
contract ReviewRegistry is EIP712 {
    using ByteHasher for bytes;

    struct Review {
        uint256 reviewId;
        address venue;
        bytes32 proofId;
        uint8 tier;
        uint8 rating;
        bytes32 contentHash;
        uint64 postedAt;
        uint256 worldIdNullifier;
    }

    struct Reply {
        bytes32 replyHash;
        uint64 postedAt;
    }

    uint8 public constant TIER_CHECKIN = 1;
    uint8 public constant TIER_SETTLED = 2;

    bytes32 public constant REPLY_TYPEHASH = keccak256("Reply(uint256 reviewId,bytes32 replyHash,uint64 deadline)");

    /// @dev World ID's Orb-verified group.
    uint256 internal constant WORLD_ID_GROUP_ID = 1;

    VenueRegistry public immutable registry;
    AttendanceGate public immutable gate;
    BillSettlement public immutable settlement;
    IWorldID public immutable worldId;

    /// @dev Pre-hashed appId; never changes across epochs.
    uint256 internal immutable appIdHash;
    /// @dev Base action string; the per-epoch suffix is appended at call time.
    string internal baseAction;
    /// @notice Length, in seconds, of one review epoch. Fixed at deployment.
    uint256 public immutable epochLength;

    uint256 public reviewCount;

    mapping(uint256 => Review) private _reviews;
    mapping(uint256 => Reply) private _replies;
    /// @dev Each attendance/settlement proof backs exactly one review.
    mapping(bytes32 => bool) public proofUsed;
    /// @dev venue => World ID nullifier => used. Keyed per venue so one human gets
    ///      one review *per venue* rather than one review globally.
    mapping(address => mapping(uint256 => bool)) public venueNullifierUsed;

    event ReviewPosted(
        uint256 indexed reviewId,
        address indexed venue,
        address indexed diner,
        bytes32 proofId,
        uint8 tier,
        uint8 rating,
        bytes32 contentHash,
        uint64 postedAt,
        uint256 worldIdNullifier
    );

    event ReplyPosted(uint256 indexed reviewId, address indexed venue, bytes32 replyHash, uint64 postedAt);

    error NoAttendanceProof();
    error NoSettlementProof();
    error ProofAlreadyUsed();
    error ProofNotOwnedByCaller();
    error VenueMismatch();
    error InvalidRating();
    error InvalidTier();
    error AlreadyReviewedVenue();
    error UnknownReview();
    error ReplyAlreadyExists();
    error ReplyDeadlineExpired();
    error BadVenueSignature();
    error ZeroEpochLength();

    constructor(
        VenueRegistry registry_,
        AttendanceGate gate_,
        BillSettlement settlement_,
        IWorldID worldId_,
        string memory appId,
        string memory action,
        uint256 epochLength_
    ) EIP712("Seated", "1") {
        if (epochLength_ == 0) revert ZeroEpochLength();

        registry = registry_;
        gate = gate_;
        settlement = settlement_;
        worldId = worldId_;
        appIdHash = abi.encodePacked(appId).hashToField();
        baseAction = action;
        epochLength = epochLength_;
    }

    /// @notice The current review epoch, derived from block.timestamp.
    function currentEpoch() public view returns (uint256) {
        return block.timestamp / epochLength;
    }

    /// @notice The World ID action string scoped to a given epoch.
    function actionForEpoch(uint256 epoch) public view returns (string memory) {
        return string.concat(baseAction, "-", Strings.toString(epoch));
    }

    /// @notice hash(appId, actionForEpoch(epoch)) that a World ID proof for that epoch must be scoped to.
    function externalNullifierHashForEpoch(uint256 epoch) public view returns (uint256) {
        return abi.encodePacked(appIdHash, actionForEpoch(epoch)).hashToField();
    }

    /// @notice The external nullifier the frontend must generate its World ID proof against right now.
    function externalNullifierHash() public view returns (uint256) {
        return externalNullifierHashForEpoch(currentEpoch());
    }

    /// @notice Post a review backed by a tier-1 check-in or a tier-2 settled bill.
    /// @dev Order matters and is demo-visible: proof resolution runs before World ID
    ///      so a wallet with no voucher fails with NoAttendanceProof, while a second
    ///      wallet belonging to an already-seen human fails with AlreadyReviewedVenue.
    /// @dev The external nullifier is derived from `block.timestamp` at execution time,
    ///      not at proof-generation time. A proof generated near an epoch boundary whose
    ///      transaction lands in the next epoch will therefore fail inside the World ID
    ///      verifier (the proof was made against the old epoch's action string). Simply
    ///      retrying — regenerating the proof against the new epoch — succeeds. This is
    ///      intentional: no grace window is offered, because a grace window would let one
    ///      human post twice within a single real-world period.
    /// @dev The same boundary has a safety side, not just this liveness one: because
    ///      epochs are fixed calendar windows rather than a rolling window per human, a
    ///      human can legitimately post one second before an epoch flips and again one
    ///      second after, two reviews seconds apart despite the nominal per-epoch limit.
    ///      This is inherent to fixed windows and accepted.
    function postReview(
        address venue,
        bytes32 proofId,
        uint8 tier,
        uint8 rating,
        bytes32 contentHash,
        uint256 worldIdRoot,
        uint256 worldIdNullifier,
        uint256[8] calldata worldIdProof
    ) external returns (uint256 reviewId) {
        if (rating == 0 || rating > 5) revert InvalidRating();
        if (proofUsed[proofId]) revert ProofAlreadyUsed();

        if (tier == TIER_CHECKIN) {
            AttendanceGate.AttendanceProof memory p = gate.proofOf(proofId);
            if (p.redeemedAt == 0) revert NoAttendanceProof();
            if (p.diner != msg.sender) revert ProofNotOwnedByCaller();
            if (p.venue != venue) revert VenueMismatch();
        } else if (tier == TIER_SETTLED) {
            BillSettlement.SettlementProof memory p = settlement.proofOf(proofId);
            if (p.settledAt == 0) revert NoSettlementProof();
            if (p.diner != msg.sender) revert ProofNotOwnedByCaller();
            if (p.venue != venue) revert VenueMismatch();
        } else {
            revert InvalidTier();
        }

        if (venueNullifierUsed[venue][worldIdNullifier]) revert AlreadyReviewedVenue();

        worldId.verifyProof(
            worldIdRoot,
            WORLD_ID_GROUP_ID,
            abi.encodePacked(venue, msg.sender).hashToField(),
            worldIdNullifier,
            externalNullifierHash(),
            worldIdProof
        );

        venueNullifierUsed[venue][worldIdNullifier] = true;
        proofUsed[proofId] = true;

        reviewId = ++reviewCount;
        _reviews[reviewId] = Review({
            reviewId: reviewId,
            venue: venue,
            proofId: proofId,
            tier: tier,
            rating: rating,
            contentHash: contentHash,
            postedAt: uint64(block.timestamp),
            worldIdNullifier: worldIdNullifier
        });

        emit ReviewPosted(
            reviewId, venue, msg.sender, proofId, tier, rating, contentHash, uint64(block.timestamp), worldIdNullifier
        );
    }

    function getReview(uint256 reviewId) external view returns (Review memory) {
        return _reviews[reviewId];
    }

    /// @notice EIP-712 digest the venue's signing key must sign to reply.
    function hashReply(uint256 reviewId, bytes32 replyHash, uint64 deadline) external view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(REPLY_TYPEHASH, reviewId, replyHash, deadline)));
    }

    /// @notice Record a venue's public reply to a review. One reply per review.
    /// @dev Signed by the same key that signs check-in vouchers: one accountable
    ///      identity produces both artifacts. Anyone may relay the transaction.
    function postReply(uint256 reviewId, bytes32 replyHash, uint64 deadline, bytes calldata signature) external {
        Review memory r = _reviews[reviewId];
        if (r.postedAt == 0) revert UnknownReview();
        if (_replies[reviewId].postedAt != 0) revert ReplyAlreadyExists();

        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(REPLY_TYPEHASH, reviewId, replyHash, deadline)));
        (address signer, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, signature);
        if (err != ECDSA.RecoverError.NoError || signer != registry.signingKeyOf(r.venue)) {
            revert BadVenueSignature();
        }

        if (block.timestamp >= deadline) revert ReplyDeadlineExpired();

        _replies[reviewId] = Reply({replyHash: replyHash, postedAt: uint64(block.timestamp)});
        emit ReplyPosted(reviewId, r.venue, replyHash, uint64(block.timestamp));
    }

    function getReply(uint256 reviewId) external view returns (Reply memory) {
        return _replies[reviewId];
    }
}
