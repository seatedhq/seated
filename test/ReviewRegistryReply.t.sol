// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VenueRegistry} from "../src/VenueRegistry.sol";
import {AttendanceGate} from "../src/AttendanceGate.sol";
import {BillSettlement} from "../src/BillSettlement.sol";
import {ReviewRegistry} from "../src/ReviewRegistry.sol";
import {IWorldID} from "../src/interfaces/IWorldID.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {MockWorldID} from "./mocks/MockWorldID.sol";

contract ReviewRegistryReplyTest is Test {
    VenueRegistry internal registry;
    AttendanceGate internal gate;
    BillSettlement internal settlement;
    ReviewRegistry internal reviews;
    MockWorldID internal worldId;

    address internal venueId = makeAddr("venue");
    address internal diner = makeAddr("diner");
    address internal relayer = makeAddr("relayer");

    uint256 internal signerPk = 0xA11CE;
    address internal signingKey;

    uint256[8] internal zeroProof;
    bytes32 internal constant REPLY_BODY = keccak256("thank you, we've passed this to the kitchen");

    uint256 internal reviewId;
    uint64 internal deadline;

    event ReplyPosted(uint256 indexed reviewId, bytes32 replyHash, uint64 postedAt);

    function setUp() public {
        signingKey = vm.addr(signerPk);

        registry = new VenueRegistry();
        gate = new AttendanceGate(registry);
        MockUSDC usdc = new MockUSDC();
        settlement = new BillSettlement(registry, IERC20(address(usdc)));
        worldId = new MockWorldID();
        reviews =
            new ReviewRegistry(registry, gate, settlement, IWorldID(address(worldId)), "app_seated", "post-review");

        vm.prank(venueId);
        registry.registerVenue(signingKey, 40, "ipfs://venue");

        vm.warp(1_800_000_000);
        deadline = uint64(block.timestamp + 1 hours);

        AttendanceGate.CheckIn memory c = AttendanceGate.CheckIn({
            venue: venueId,
            diner: diner,
            seatedAt: uint64(block.timestamp),
            expiry: uint64(block.timestamp + 2 hours),
            salt: bytes32(uint256(1))
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, gate.hashCheckIn(c));
        vm.prank(diner);
        bytes32 proofId = gate.redeem(c, abi.encodePacked(r, s, v));

        vm.prank(diner);
        reviewId = reviews.postReview(venueId, proofId, 1, 4, keccak256("good"), 111, 222, zeroProof);
    }

    function _signReply(uint256 id, bytes32 body, uint64 dl, uint256 pk) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, reviews.hashReply(id, body, dl));
        return abi.encodePacked(r, s, v);
    }

    function test_postReply_storesReply() public {
        reviews.postReply(reviewId, REPLY_BODY, deadline, _signReply(reviewId, REPLY_BODY, deadline, signerPk));

        ReviewRegistry.Reply memory reply = reviews.getReply(reviewId);
        assertEq(reply.replyHash, REPLY_BODY);
        assertEq(reply.postedAt, uint64(block.timestamp));
    }

    function test_postReply_emitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit ReplyPosted(reviewId, REPLY_BODY, uint64(block.timestamp));

        reviews.postReply(reviewId, REPLY_BODY, deadline, _signReply(reviewId, REPLY_BODY, deadline, signerPk));
    }

    /// The signature carries the authority, so any relayer may submit it.
    /// NOTE: the signature must be computed BEFORE vm.prank, not inline as a call
    /// argument. Solidity evaluates call arguments before the call itself, so
    /// `_signReply(...)`'s internal external call to `reviews.hashReply(...)` would
    /// run first and consume the prank; `postReply` would then execute as this test
    /// contract, not as `relayer`, silently defeating the point of the test.
    function test_postReply_anyoneMaySubmitAVenueSignedReply() public {
        bytes memory sig = _signReply(reviewId, REPLY_BODY, deadline, signerPk);

        vm.prank(relayer);
        reviews.postReply(reviewId, REPLY_BODY, deadline, sig);

        assertEq(reviews.getReply(reviewId).replyHash, REPLY_BODY);
    }

    function test_postReply_revertsForUnknownReview() public {
        uint256 missing = 999;
        bytes memory sig = _signReply(missing, REPLY_BODY, deadline, signerPk);

        vm.expectRevert(ReviewRegistry.UnknownReview.selector);
        reviews.postReply(missing, REPLY_BODY, deadline, sig);
    }

    function test_postReply_revertsOnSecondReply() public {
        reviews.postReply(reviewId, REPLY_BODY, deadline, _signReply(reviewId, REPLY_BODY, deadline, signerPk));

        bytes32 second = keccak256("actually, on reflection");
        bytes memory sig = _signReply(reviewId, second, deadline, signerPk);
        vm.expectRevert(ReviewRegistry.ReplyAlreadyExists.selector);
        reviews.postReply(reviewId, second, deadline, sig);
    }

    function test_postReply_revertsWhenSignedByWrongKey() public {
        bytes memory sig = _signReply(reviewId, REPLY_BODY, deadline, 0xBAD);

        vm.expectRevert(ReviewRegistry.BadVenueSignature.selector);
        reviews.postReply(reviewId, REPLY_BODY, deadline, sig);
    }

    function test_postReply_revertsOnMalformedSignature() public {
        vm.expectRevert(ReviewRegistry.BadVenueSignature.selector);
        reviews.postReply(reviewId, REPLY_BODY, deadline, hex"deadbeef");
    }

    /// Tampering with the body invalidates the signature.
    function test_postReply_revertsWhenBodyDoesNotMatchSignature() public {
        bytes memory sig = _signReply(reviewId, REPLY_BODY, deadline, signerPk);

        vm.expectRevert(ReviewRegistry.BadVenueSignature.selector);
        reviews.postReply(reviewId, keccak256("something else entirely"), deadline, sig);
    }

    function test_postReply_revertsAfterDeadline() public {
        bytes memory sig = _signReply(reviewId, REPLY_BODY, deadline, signerPk);
        vm.warp(deadline + 1);

        vm.expectRevert(ReviewRegistry.ReplyDeadlineExpired.selector);
        reviews.postReply(reviewId, REPLY_BODY, deadline, sig);
    }

    /// A rotated signing key can reply; the old key cannot.
    function test_postReply_followsSigningKeyRotation() public {
        uint256 newPk = 0xB0B;
        vm.prank(venueId);
        registry.setSigningKey(venueId, vm.addr(newPk));

        bytes memory oldSig = _signReply(reviewId, REPLY_BODY, deadline, signerPk);
        vm.expectRevert(ReviewRegistry.BadVenueSignature.selector);
        reviews.postReply(reviewId, REPLY_BODY, deadline, oldSig);

        bytes memory newSig = _signReply(reviewId, REPLY_BODY, deadline, newPk);
        reviews.postReply(reviewId, REPLY_BODY, deadline, newSig);
        assertEq(reviews.getReply(reviewId).replyHash, REPLY_BODY);
    }

    function test_getReply_isEmptyBeforeAnyReply() public view {
        assertEq(reviews.getReply(reviewId).postedAt, 0);
    }

    /// Pins the exact EIP-712 typehash string. Round-trip signing tests alone
    /// cannot catch a field rename here: hashReply() and postReply() both derive
    /// their digest from the same REPLY_TYPEHASH symbol, so as long as they agree
    /// with each other, a mutated-but-internally-consistent string still verifies.
    /// This test independently pins the literal so client integrations that
    /// construct the typehash themselves stay compatible.
    function test_REPLY_TYPEHASH_isPinned() public view {
        assertEq(reviews.REPLY_TYPEHASH(), keccak256("Reply(uint256 reviewId,bytes32 replyHash,uint64 deadline)"));
    }
}
