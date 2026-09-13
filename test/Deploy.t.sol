// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {VenueRegistry} from "../src/VenueRegistry.sol";
import {AttendanceGate} from "../src/AttendanceGate.sol";
import {BillSettlement} from "../src/BillSettlement.sol";
import {ReviewRegistry} from "../src/ReviewRegistry.sol";

contract DeployTest is Test {
    function test_run_wiresContractsTogether() public {
        Deploy deployer = new Deploy();
        Deploy.Deployment memory d = deployer.deploy(makeAddr("usdc"), makeAddr("worldId"), "app_seated", "post-review");

        assertEq(address(AttendanceGate(d.gate).registry()), d.registry);
        assertEq(address(BillSettlement(d.settlement).registry()), d.registry);
        assertEq(address(ReviewRegistry(d.reviews).registry()), d.registry);
        assertEq(address(ReviewRegistry(d.reviews).gate()), d.gate);
        assertEq(address(ReviewRegistry(d.reviews).settlement()), d.settlement);
    }

    function test_run_usesSeatedEip712DomainInBothSigningContracts() public {
        Deploy deployer = new Deploy();
        Deploy.Deployment memory d = deployer.deploy(makeAddr("usdc"), makeAddr("worldId"), "app_seated", "post-review");

        (, string memory gateName, string memory gateVersion,,,,) = AttendanceGate(d.gate).eip712Domain();
        (, string memory reviewName, string memory reviewVersion,,,,) = ReviewRegistry(d.reviews).eip712Domain();

        assertEq(gateName, "Seated");
        assertEq(gateVersion, "1");
        assertEq(reviewName, "Seated");
        assertEq(reviewVersion, "1");
    }
}
