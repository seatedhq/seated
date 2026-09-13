// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {VenueRegistry} from "../src/VenueRegistry.sol";

contract VenueRegistryTest is Test {
    VenueRegistry internal registry;

    address internal venueId = makeAddr("venue");
    address internal signingKey = makeAddr("signingKey");
    address internal stranger = makeAddr("stranger");

    event VenueRegistered(
        address indexed venueId, address indexed owner, address signingKey, uint32 maxCoversPerDay, string metadataURI
    );
    event SigningKeyUpdated(address indexed venueId, address newSigningKey);
    event VenueActiveSet(address indexed venueId, bool active);

    function setUp() public {
        registry = new VenueRegistry();
    }

    function _register() internal {
        vm.prank(venueId);
        registry.registerVenue(signingKey, 40, "ipfs://venue-metadata");
    }

    function test_registerVenue_storesAllFields() public {
        _register();

        VenueRegistry.Venue memory v = registry.getVenue(venueId);
        assertEq(v.owner, venueId);
        assertEq(v.signingKey, signingKey);
        assertEq(v.maxCoversPerDay, 40);
        assertEq(v.metadataURI, "ipfs://venue-metadata");
        assertTrue(v.active);
    }

    function test_registerVenue_emitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit VenueRegistered(venueId, venueId, signingKey, 40, "ipfs://venue-metadata");

        vm.prank(venueId);
        registry.registerVenue(signingKey, 40, "ipfs://venue-metadata");
    }

    function test_registerVenue_revertsOnDoubleRegistration() public {
        _register();

        vm.prank(venueId);
        vm.expectRevert(VenueRegistry.VenueAlreadyRegistered.selector);
        registry.registerVenue(signingKey, 40, "ipfs://other");
    }

    function test_registerVenue_revertsOnZeroSigningKey() public {
        vm.prank(venueId);
        vm.expectRevert(VenueRegistry.ZeroSigningKey.selector);
        registry.registerVenue(address(0), 40, "ipfs://venue-metadata");
    }

    function test_registerVenue_revertsOnZeroCapacity() public {
        vm.prank(venueId);
        vm.expectRevert(VenueRegistry.ZeroCapacity.selector);
        registry.registerVenue(signingKey, 0, "ipfs://venue-metadata");
    }

    function test_setSigningKey_rotatesKey() public {
        _register();
        address newKey = makeAddr("newKey");

        vm.expectEmit(true, false, false, true);
        emit SigningKeyUpdated(venueId, newKey);

        vm.prank(venueId);
        registry.setSigningKey(venueId, newKey);

        assertEq(registry.signingKeyOf(venueId), newKey);
    }

    function test_setSigningKey_revertsForNonOwner() public {
        _register();

        vm.prank(stranger);
        vm.expectRevert(VenueRegistry.NotVenueOwner.selector);
        registry.setSigningKey(venueId, stranger);
    }

    function test_setSigningKey_revertsOnZeroSigningKey() public {
        _register();

        vm.prank(venueId);
        vm.expectRevert(VenueRegistry.ZeroSigningKey.selector);
        registry.setSigningKey(venueId, address(0));
    }

    function test_setSigningKey_revertsOnUnregisteredVenue() public {
        vm.prank(venueId);
        vm.expectRevert(VenueRegistry.VenueNotRegistered.selector);
        registry.setSigningKey(venueId, makeAddr("newKey"));
    }

    function test_setActive_deactivatesVenue() public {
        _register();

        vm.expectEmit(true, false, false, true);
        emit VenueActiveSet(venueId, false);

        vm.prank(venueId);
        registry.setActive(venueId, false);

        assertFalse(registry.isActive(venueId));
    }

    function test_setActive_revertsForNonOwner() public {
        _register();

        vm.prank(stranger);
        vm.expectRevert(VenueRegistry.NotVenueOwner.selector);
        registry.setActive(venueId, false);
    }

    function test_setActive_revertsOnUnregisteredVenue() public {
        vm.prank(venueId);
        vm.expectRevert(VenueRegistry.VenueNotRegistered.selector);
        registry.setActive(venueId, false);
    }

    function test_unregisteredVenue_readsAsInactive() public view {
        assertFalse(registry.isActive(venueId));
        assertEq(registry.signingKeyOf(venueId), address(0));
        assertEq(registry.maxCoversPerDayOf(venueId), 0);
    }
}
