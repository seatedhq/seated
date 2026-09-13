// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VenueRegistry} from "../src/VenueRegistry.sol";
import {AttendanceGate} from "../src/AttendanceGate.sol";
import {BillSettlement} from "../src/BillSettlement.sol";
import {ReviewRegistry} from "../src/ReviewRegistry.sol";
import {IWorldID} from "../src/interfaces/IWorldID.sol";
import {ByteHasher} from "../src/libraries/ByteHasher.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {MockWorldID} from "./mocks/MockWorldID.sol";

contract ReviewRegistryTest is Test {
    using ByteHasher for bytes;

    VenueRegistry internal registry;
    AttendanceGate internal gate;
    BillSettlement internal settlement;
    ReviewRegistry internal reviews;
    MockUSDC internal usdc;
    MockWorldID internal worldId;

    address internal venueId = makeAddr("venue");
    address internal otherVenueId = makeAddr("otherVenue");
    address internal diner = makeAddr("diner");

    uint256 internal signerPk = 0xA11CE;
    address internal signingKey;

    uint256 internal constant WORLD_ROOT = 111;
    uint256 internal constant NULLIFIER = 222;
    uint256[8] internal zeroProof;

    bytes32 internal constant CONTENT = keccak256("the sea bass was excellent");

    function setUp() public {
        signingKey = vm.addr(signerPk);

        registry = new VenueRegistry();
        gate = new AttendanceGate(registry);
        usdc = new MockUSDC();
        settlement = new BillSettlement(registry, IERC20(address(usdc)));
        worldId = new MockWorldID();
        reviews =
            new ReviewRegistry(registry, gate, settlement, IWorldID(address(worldId)), "app_seated", "post-review");

        vm.prank(venueId);
        registry.registerVenue(signingKey, 40, "ipfs://venue");
        vm.prank(otherVenueId);
        registry.registerVenue(signingKey, 40, "ipfs://other");

        usdc.mint(diner, 1_000_000_000);
        vm.prank(diner);
        usdc.approve(address(settlement), type(uint256).max);

        vm.warp(1_800_000_000);
    }

    function _redeemCheckIn(address venue, address diner_, bytes32 salt) internal returns (bytes32) {
        AttendanceGate.CheckIn memory c = AttendanceGate.CheckIn({
            venue: venue,
            diner: diner_,
            seatedAt: uint64(block.timestamp),
            expiry: uint64(block.timestamp + 2 hours),
            salt: salt
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, gate.hashCheckIn(c));

        vm.prank(diner_);
        return gate.redeem(c, abi.encodePacked(r, s, v));
    }

    function _post(address caller, address venue, bytes32 proofId, uint8 tier, uint256 nullifier)
        internal
        returns (uint256)
    {
        vm.prank(caller);
        return reviews.postReview(venue, proofId, tier, 5, CONTENT, WORLD_ROOT, nullifier, zeroProof);
    }

    // --- tier 1 ---

    function test_postReview_tier1_storesReview() public {
        bytes32 proofId = _redeemCheckIn(venueId, diner, bytes32(uint256(1)));
        uint256 id = _post(diner, venueId, proofId, 1, NULLIFIER);

        assertEq(id, 1, "review ids start at 1");

        ReviewRegistry.Review memory r = reviews.getReview(id);
        assertEq(r.reviewId, 1);
        assertEq(r.venue, venueId);
        assertEq(r.proofId, proofId);
        assertEq(r.tier, 1);
        assertEq(r.rating, 5);
        assertEq(r.contentHash, CONTENT);
        assertEq(r.postedAt, uint64(block.timestamp));
        assertEq(r.worldIdNullifier, NULLIFIER);
    }

    /// The Scene 2 attack: a wallet with no voucher at all. World ID is made to
    /// reject so that, if verification ran before proof resolution, the revert
    /// reason would flip to MockWorldIdRejected instead of NoAttendanceProof.
    /// This pins the demo-critical check order from the brief.
    function test_postReview_revertsWithNoAttendanceProof_forUnknownProofId() public {
        worldId.setShouldReject(true);

        vm.prank(diner);
        vm.expectRevert(ReviewRegistry.NoAttendanceProof.selector);
        reviews.postReview(venueId, bytes32(uint256(0xdead)), 1, 5, CONTENT, WORLD_ROOT, NULLIFIER, zeroProof);
    }

    function test_postReview_revertsWhenProofBelongsToSomeoneElse() public {
        bytes32 proofId = _redeemCheckIn(venueId, diner, bytes32(uint256(1)));

        vm.prank(makeAddr("thief"));
        vm.expectRevert(ReviewRegistry.ProofNotOwnedByCaller.selector);
        reviews.postReview(venueId, proofId, 1, 5, CONTENT, WORLD_ROOT, NULLIFIER, zeroProof);
    }

    function test_postReview_revertsWhenProofIsForADifferentVenue() public {
        bytes32 proofId = _redeemCheckIn(venueId, diner, bytes32(uint256(1)));

        vm.prank(diner);
        vm.expectRevert(ReviewRegistry.VenueMismatch.selector);
        reviews.postReview(otherVenueId, proofId, 1, 5, CONTENT, WORLD_ROOT, NULLIFIER, zeroProof);
    }

    function test_postReview_revertsWhenProofAlreadySpent() public {
        bytes32 proofId = _redeemCheckIn(venueId, diner, bytes32(uint256(1)));
        _post(diner, venueId, proofId, 1, NULLIFIER);

        vm.prank(diner);
        vm.expectRevert(ReviewRegistry.ProofAlreadyUsed.selector);
        reviews.postReview(venueId, proofId, 1, 5, CONTENT, WORLD_ROOT, NULLIFIER + 1, zeroProof);
    }

    // --- the Scene 2 sybil defence ---

    /// One human, many wallets, every wallet holding a genuinely valid voucher.
    /// The first review lands; all the others are rejected by the World ID nullifier.
    function test_postReview_oneHumanCannotReviewSameVenueTwice() public {
        address walletA = address(uint160(0x1000));
        address walletB = address(uint160(0x1001));

        bytes32 proofA = _redeemCheckIn(venueId, walletA, bytes32(uint256(1)));
        bytes32 proofB = _redeemCheckIn(venueId, walletB, bytes32(uint256(2)));

        _post(walletA, venueId, proofA, 1, NULLIFIER);

        vm.prank(walletB);
        vm.expectRevert(ReviewRegistry.AlreadyReviewedVenue.selector);
        reviews.postReview(venueId, proofB, 1, 5, CONTENT, WORLD_ROOT, NULLIFIER, zeroProof);
    }

    /// ...but the same human may review a *different* venue.
    function test_postReview_sameHumanMayReviewADifferentVenue() public {
        bytes32 proofHere = _redeemCheckIn(venueId, diner, bytes32(uint256(1)));
        bytes32 proofThere = _redeemCheckIn(otherVenueId, diner, bytes32(uint256(2)));

        _post(diner, venueId, proofHere, 1, NULLIFIER);
        uint256 second = _post(diner, otherVenueId, proofThere, 1, NULLIFIER);

        assertEq(second, 2);
    }

    function test_postReview_revertsWhenWorldIdProofIsInvalid() public {
        bytes32 proofId = _redeemCheckIn(venueId, diner, bytes32(uint256(1)));
        worldId.setShouldReject(true);

        vm.prank(diner);
        vm.expectRevert(MockWorldID.MockWorldIdRejected.selector);
        reviews.postReview(venueId, proofId, 1, 5, CONTENT, WORLD_ROOT, NULLIFIER, zeroProof);
    }

    /// The World ID signal must bind both the venue and the caller, so a proof
    /// cannot be replayed by a different submitter.
    function test_postReview_passesVenueAndCallerAsWorldIdSignal() public {
        bytes32 proofId = _redeemCheckIn(venueId, diner, bytes32(uint256(1)));

        vm.expectCall(
            address(worldId),
            abi.encodeWithSelector(
                IWorldID.verifyProof.selector,
                WORLD_ROOT,
                uint256(1),
                abi.encodePacked(venueId, diner).hashToField(),
                NULLIFIER,
                reviews.externalNullifierHash(),
                zeroProof
            )
        );

        _post(diner, venueId, proofId, 1, NULLIFIER);
    }

    /// Regression for the signal-binding vulnerability: an attacker who observes a
    /// victim's public (root, nullifier, proof) tuple in the mempool must not be
    /// able to submit it themselves and burn the victim's World ID nullifier at
    /// that venue. Both diners hold genuine attendance vouchers; only the World ID
    /// tuple is lifted. Because the signal now binds `msg.sender`, the attacker's
    /// replay is rejected by the (signal-aware) World ID router rather than
    /// succeeding and permanently silencing the victim.
    function test_postReview_worldIdSignalCannotBeReplayedByAnotherCaller() public {
        address victim = makeAddr("victim");
        address attacker = makeAddr("attacker");

        bytes32 victimProof = _redeemCheckIn(venueId, victim, bytes32(uint256(1)));
        bytes32 attackerProof = _redeemCheckIn(venueId, attacker, bytes32(uint256(2)));

        // The mock now behaves like the real router: it only accepts a signal
        // bound to the actual caller (the victim), so the attacker's submission
        // of the victim's tuple must revert rather than silently succeed.
        worldId.setExpectedSignal(abi.encodePacked(venueId, victim).hashToField());

        vm.prank(attacker);
        vm.expectRevert(MockWorldID.MockWorldIdSignalMismatch.selector);
        reviews.postReview(venueId, attackerProof, 1, 5, CONTENT, WORLD_ROOT, NULLIFIER, zeroProof);

        // The victim, submitting their own tuple as themselves, succeeds.
        _post(victim, venueId, victimProof, 1, NULLIFIER);
    }

    // --- tier 2 ---

    function test_postReview_tier2_acceptsSettlementProof() public {
        vm.prank(diner);
        bytes32 proofId = settlement.settle(venueId, 42_500_000);

        uint256 id = _post(diner, venueId, proofId, 2, NULLIFIER);

        ReviewRegistry.Review memory r = reviews.getReview(id);
        assertEq(r.tier, 2);
        assertEq(r.proofId, proofId);
    }

    function test_postReview_tier2_revertsForUnknownSettlement() public {
        vm.prank(diner);
        vm.expectRevert(ReviewRegistry.NoSettlementProof.selector);
        reviews.postReview(venueId, bytes32(uint256(0xdead)), 2, 5, CONTENT, WORLD_ROOT, NULLIFIER, zeroProof);
    }

    /// A tier-1 proofId must not be accepted when the caller claims tier 2.
    function test_postReview_revertsWhenTierDoesNotMatchProofSource() public {
        bytes32 checkInProof = _redeemCheckIn(venueId, diner, bytes32(uint256(1)));

        vm.prank(diner);
        vm.expectRevert(ReviewRegistry.NoSettlementProof.selector);
        reviews.postReview(venueId, checkInProof, 2, 5, CONTENT, WORLD_ROOT, NULLIFIER, zeroProof);
    }

    // --- validation ---

    function test_postReview_revertsOnInvalidTier() public {
        bytes32 proofId = _redeemCheckIn(venueId, diner, bytes32(uint256(1)));

        vm.prank(diner);
        vm.expectRevert(ReviewRegistry.InvalidTier.selector);
        reviews.postReview(venueId, proofId, 3, 5, CONTENT, WORLD_ROOT, NULLIFIER, zeroProof);
    }

    function test_postReview_revertsOnRatingZero() public {
        bytes32 proofId = _redeemCheckIn(venueId, diner, bytes32(uint256(1)));

        vm.prank(diner);
        vm.expectRevert(ReviewRegistry.InvalidRating.selector);
        reviews.postReview(venueId, proofId, 1, 0, CONTENT, WORLD_ROOT, NULLIFIER, zeroProof);
    }

    function test_postReview_revertsOnRatingAboveFive() public {
        bytes32 proofId = _redeemCheckIn(venueId, diner, bytes32(uint256(1)));

        vm.prank(diner);
        vm.expectRevert(ReviewRegistry.InvalidRating.selector);
        reviews.postReview(venueId, proofId, 1, 6, CONTENT, WORLD_ROOT, NULLIFIER, zeroProof);
    }
}
