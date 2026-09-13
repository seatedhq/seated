// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {VenueRegistry} from "../src/VenueRegistry.sol";

/// @dev Registers the three demo venues. Each venue is registered by its own key,
///      because the registering address becomes the venue id.
contract SeedVenues is Script {
    function run() external {
        VenueRegistry registry = VenueRegistry(vm.envAddress("VENUE_REGISTRY"));

        uint256[3] memory venuePks =
            [vm.envUint("VENUE_1_PRIVATE_KEY"), vm.envUint("VENUE_2_PRIVATE_KEY"), vm.envUint("VENUE_3_PRIVATE_KEY")];
        address[3] memory signingKeys = [
            vm.envAddress("VENUE_1_SIGNING_KEY"),
            vm.envAddress("VENUE_2_SIGNING_KEY"),
            vm.envAddress("VENUE_3_SIGNING_KEY")
        ];
        uint32[3] memory capacities = [uint32(40), uint32(120), uint32(24)];
        string[3] memory metadata = [
            vm.envString("VENUE_1_METADATA_URI"),
            vm.envString("VENUE_2_METADATA_URI"),
            vm.envString("VENUE_3_METADATA_URI")
        ];

        for (uint256 i = 0; i < 3; i++) {
            vm.startBroadcast(venuePks[i]);
            registry.registerVenue(signingKeys[i], capacities[i], metadata[i]);
            vm.stopBroadcast();

            console2.log("Registered venue", vm.addr(venuePks[i]));
        }
    }
}
