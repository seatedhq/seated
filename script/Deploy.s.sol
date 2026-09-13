// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VenueRegistry} from "../src/VenueRegistry.sol";
import {AttendanceGate} from "../src/AttendanceGate.sol";
import {BillSettlement} from "../src/BillSettlement.sol";
import {ReviewRegistry} from "../src/ReviewRegistry.sol";
import {IWorldID} from "../src/interfaces/IWorldID.sol";

contract Deploy is Script {
    struct Deployment {
        address registry;
        address gate;
        address settlement;
        address reviews;
    }

    /// @dev Pure deployment logic, callable from tests without broadcasting.
    function deploy(address usdc, address worldIdRouter, string memory appId, string memory action, uint256 epochLength)
        public
        returns (Deployment memory)
    {
        VenueRegistry registry = new VenueRegistry();
        AttendanceGate gate = new AttendanceGate(registry);
        BillSettlement settlement = new BillSettlement(registry, IERC20(usdc));
        ReviewRegistry reviews =
            new ReviewRegistry(registry, gate, settlement, IWorldID(worldIdRouter), appId, action, epochLength);

        return Deployment({
            registry: address(registry), gate: address(gate), settlement: address(settlement), reviews: address(reviews)
        });
    }

    function run() external {
        address usdc = vm.envAddress("USDC_ADDRESS");
        address worldIdRouter = vm.envAddress("WORLD_ID_ROUTER");
        string memory appId = vm.envString("WORLD_ID_APP_ID");
        string memory action = vm.envString("WORLD_ID_ACTION");
        uint256 epochLength = vm.envUint("REVIEW_EPOCH_LENGTH");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        Deployment memory d = deploy(usdc, worldIdRouter, appId, action, epochLength);
        vm.stopBroadcast();

        console2.log("VenueRegistry  ", d.registry);
        console2.log("AttendanceGate ", d.gate);
        console2.log("BillSettlement ", d.settlement);
        console2.log("ReviewRegistry ", d.reviews);
        console2.log("startBlock    ", block.number);
    }
}
