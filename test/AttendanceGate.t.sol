// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {VenueRegistry} from "../src/VenueRegistry.sol";
import {AttendanceGate} from "../src/AttendanceGate.sol";

contract AttendanceGateTest is Test {
    VenueRegistry internal registry;
    AttendanceGate internal gate;

    address internal venueId = makeAddr("venue");
    address internal diner = makeAddr("diner");

    uint256 internal signerPk = 0xA11CE;
    address internal signingKey;

    uint32 internal constant CAPACITY = 3;

    function setUp() public {
        signingKey = vm.addr(signerPk);

        registry = new VenueRegistry();
        gate = new AttendanceGate(registry);

        vm.prank(venueId);
        registry.registerVenue(signingKey, CAPACITY, "ipfs://venue");

        // Move off timestamp 0 so `expiry` arithmetic is meaningful.
        vm.warp(1_800_000_000);
    }

    function _voucher(address diner_, bytes32 salt) internal view returns (AttendanceGate.CheckIn memory) {
        return AttendanceGate.CheckIn({
            venue: venueId,
            diner: diner_,
            seatedAt: uint64(block.timestamp),
            expiry: uint64(block.timestamp + 2 hours),
            salt: salt
        });
    }

    function _sign(AttendanceGate.CheckIn memory checkIn, uint256 pk) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, gate.hashCheckIn(checkIn));
        return abi.encodePacked(r, s, v);
    }

    function test_redeem_storesProofAndReturnsNullifierAsProofId() public {
        AttendanceGate.CheckIn memory c = _voucher(diner, bytes32(uint256(1)));
        bytes memory sig = _sign(c, signerPk);

        vm.prank(diner);
        bytes32 proofId = gate.redeem(c, sig);

        assertEq(proofId, keccak256(abi.encode(venueId, diner, c.salt)));

        AttendanceGate.AttendanceProof memory p = gate.proofOf(proofId);
        assertEq(p.venue, venueId);
        assertEq(p.diner, diner);
        assertEq(p.redeemedAt, uint64(block.timestamp));
    }

    function test_redeem_revertsOnWrongSigner() public {
        AttendanceGate.CheckIn memory c = _voucher(diner, bytes32(uint256(1)));
        uint256 attackerPk = 0xBAD;
        bytes memory sig = _sign(c, attackerPk);

        vm.prank(diner);
        vm.expectRevert(AttendanceGate.BadVenueSignature.selector);
        gate.redeem(c, sig);
    }

    function test_redeem_revertsOnMalformedSignature() public {
        AttendanceGate.CheckIn memory c = _voucher(diner, bytes32(uint256(1)));

        vm.prank(diner);
        vm.expectRevert(AttendanceGate.BadVenueSignature.selector);
        gate.redeem(c, hex"deadbeef");
    }

    function test_redeem_revertsWhenExpired() public {
        AttendanceGate.CheckIn memory c = _voucher(diner, bytes32(uint256(1)));
        bytes memory sig = _sign(c, signerPk);

        vm.warp(c.expiry + 1);

        vm.prank(diner);
        vm.expectRevert(AttendanceGate.VoucherExpired.selector);
        gate.redeem(c, sig);
    }

    function test_redeem_revertsOnReplay() public {
        AttendanceGate.CheckIn memory c = _voucher(diner, bytes32(uint256(1)));
        bytes memory sig = _sign(c, signerPk);

        vm.prank(diner);
        gate.redeem(c, sig);

        vm.prank(diner);
        vm.expectRevert(AttendanceGate.VoucherUsed.selector);
        gate.redeem(c, sig);
    }

    function test_redeem_revertsWhenCallerIsNotTheNamedDiner() public {
        AttendanceGate.CheckIn memory c = _voucher(diner, bytes32(uint256(1)));
        bytes memory sig = _sign(c, signerPk);

        vm.prank(makeAddr("someoneElse"));
        vm.expectRevert(AttendanceGate.NotVoucherDiner.selector);
        gate.redeem(c, sig);
    }

    function test_redeem_enforcesDailyCapacity() public {
        // Fill the venue to its committed capacity with distinct diners.
        for (uint256 i = 0; i < CAPACITY; i++) {
            address d = address(uint160(0x1000 + i));
            AttendanceGate.CheckIn memory c = _voucher(d, bytes32(i));
            bytes memory sig = _sign(c, signerPk);
            vm.prank(d);
            gate.redeem(c, sig);
        }

        address overflowDiner = address(uint160(0x2000));
        AttendanceGate.CheckIn memory overflow = _voucher(overflowDiner, bytes32(uint256(99)));
        bytes memory overflowSig = _sign(overflow, signerPk);

        vm.prank(overflowDiner);
        vm.expectRevert(AttendanceGate.CapacityExceeded.selector);
        gate.redeem(overflow, overflowSig);
    }

    function test_redeem_capacityResetsNextDay() public {
        for (uint256 i = 0; i < CAPACITY; i++) {
            address d = address(uint160(0x1000 + i));
            AttendanceGate.CheckIn memory c = _voucher(d, bytes32(i));
            bytes memory sig = _sign(c, signerPk);
            vm.prank(d);
            gate.redeem(c, sig);
        }

        vm.warp(block.timestamp + 1 days);

        address nextDayDiner = address(uint160(0x3000));
        AttendanceGate.CheckIn memory c2 = _voucher(nextDayDiner, bytes32(uint256(77)));
        bytes memory sig2 = _sign(c2, signerPk);

        vm.prank(nextDayDiner);
        bytes32 proofId = gate.redeem(c2, sig2);

        assertEq(gate.proofOf(proofId).diner, nextDayDiner);
    }

    function test_redeem_revertsForInactiveVenue() public {
        vm.prank(venueId);
        registry.setActive(venueId, false);

        AttendanceGate.CheckIn memory c = _voucher(diner, bytes32(uint256(1)));
        bytes memory sig = _sign(c, signerPk);

        vm.prank(diner);
        vm.expectRevert(AttendanceGate.VenueNotActive.selector);
        gate.redeem(c, sig);
    }

    function test_redeem_nullifierCheckPrecedesCapacityCheck() public {
        // Voucher A is redeemed first, then the venue is filled to capacity with
        // two more distinct diners, so voucher A is now both already-used AND the
        // venue is at its 3/3 daily cap. Replaying it must surface VoucherUsed, not
        // CapacityExceeded — proving the nullifier check runs before capacity.
        AttendanceGate.CheckIn memory a = _voucher(diner, bytes32(uint256(1)));
        bytes memory sigA = _sign(a, signerPk);

        vm.prank(diner);
        gate.redeem(a, sigA);

        for (uint256 i = 0; i < CAPACITY - 1; i++) {
            address d = address(uint160(0x1000 + i));
            AttendanceGate.CheckIn memory c = _voucher(d, bytes32(i + 1));
            bytes memory sig = _sign(c, signerPk);
            vm.prank(d);
            gate.redeem(c, sig);
        }

        vm.prank(diner);
        vm.expectRevert(AttendanceGate.VoucherUsed.selector);
        gate.redeem(a, sigA);
    }

    function test_redeem_signatureCheckPrecedesExpiryCheck() public {
        // Voucher is both badly-signed AND expired. BadVenueSignature must win,
        // proving the signature check runs before the expiry check.
        AttendanceGate.CheckIn memory c = _voucher(diner, bytes32(uint256(1)));
        uint256 attackerPk = 0xBAD;
        bytes memory sig = _sign(c, attackerPk);

        vm.warp(c.expiry + 1);

        vm.prank(diner);
        vm.expectRevert(AttendanceGate.BadVenueSignature.selector);
        gate.redeem(c, sig);
    }

    function test_redeem_revertsExactlyAtExpiryBoundary() public {
        // The contract uses `block.timestamp >= checkIn.expiry`, so the exact
        // expiry timestamp itself must already revert.
        AttendanceGate.CheckIn memory c = _voucher(diner, bytes32(uint256(1)));
        bytes memory sig = _sign(c, signerPk);

        vm.warp(c.expiry);

        vm.prank(diner);
        vm.expectRevert(AttendanceGate.VoucherExpired.selector);
        gate.redeem(c, sig);
    }

    function test_proofOf_unknownIdIsEmpty() public view {
        AttendanceGate.AttendanceProof memory p = gate.proofOf(bytes32(uint256(0xdead)));
        assertEq(p.redeemedAt, 0);
        assertEq(p.venue, address(0));
    }
}
