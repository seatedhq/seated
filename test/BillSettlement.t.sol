// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VenueRegistry} from "../src/VenueRegistry.sol";
import {BillSettlement} from "../src/BillSettlement.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

contract BillSettlementTest is Test {
    VenueRegistry internal registry;
    BillSettlement internal settlement;
    MockUSDC internal usdc;

    address internal venueId = makeAddr("venue");
    address internal diner = makeAddr("diner");

    uint256 internal constant BILL = 42_500_000; // 42.50 USDC

    function setUp() public {
        registry = new VenueRegistry();
        usdc = new MockUSDC();
        settlement = new BillSettlement(registry, IERC20(address(usdc)));

        vm.prank(venueId);
        registry.registerVenue(makeAddr("signingKey"), 40, "ipfs://venue");

        usdc.mint(diner, 1_000_000_000);
        vm.prank(diner);
        usdc.approve(address(settlement), type(uint256).max);

        vm.warp(1_800_000_000);
    }

    function test_settle_movesUsdcToVenueOwner() public {
        vm.prank(diner);
        settlement.settle(venueId, BILL);

        assertEq(usdc.balanceOf(venueId), BILL);
        assertEq(usdc.balanceOf(diner), 1_000_000_000 - BILL);
        assertEq(usdc.balanceOf(address(settlement)), 0, "settlement must not hold funds");
    }

    function test_settle_recordsProof() public {
        vm.prank(diner);
        bytes32 proofId = settlement.settle(venueId, BILL);

        BillSettlement.SettlementProof memory p = settlement.proofOf(proofId);
        assertEq(p.venue, venueId);
        assertEq(p.diner, diner);
        assertEq(p.amount, BILL);
        assertEq(p.settledAt, uint64(block.timestamp));
    }

    function test_settle_producesUniqueProofIdsForIdenticalPaymentsInSameBlock() public {
        vm.prank(diner);
        bytes32 first = settlement.settle(venueId, BILL);

        vm.prank(diner);
        bytes32 second = settlement.settle(venueId, BILL);

        assertTrue(first != second, "proofId collision");
    }

    function test_settle_revertsOnZeroAmount() public {
        vm.prank(diner);
        vm.expectRevert(BillSettlement.ZeroAmount.selector);
        settlement.settle(venueId, 0);
    }

    function test_settle_revertsForInactiveVenue() public {
        vm.prank(venueId);
        registry.setActive(venueId, false);

        vm.prank(diner);
        vm.expectRevert(BillSettlement.VenueNotActive.selector);
        settlement.settle(venueId, BILL);
    }

    function test_settle_revertsWithoutAllowance() public {
        address broke = makeAddr("broke");
        usdc.mint(broke, BILL);

        vm.prank(broke);
        vm.expectRevert();
        settlement.settle(venueId, BILL);
    }

    function test_proofOf_unknownIdIsEmpty() public view {
        BillSettlement.SettlementProof memory p = settlement.proofOf(bytes32(uint256(0xdead)));
        assertEq(p.settledAt, 0);
    }
}
