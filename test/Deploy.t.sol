// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {ProofSwarm} from "../src/ProofSwarm.sol";
import {CertificateChecker} from "../src/CertificateChecker.sol";

contract DeployTest is Test {
    function test_DeployGivesTheSwarmToTheNamedOwner() public {
        address owner = makeAddr("owner");
        Deploy script = new Deploy();
        vm.prank(makeAddr("whoever runs the script"));
        (ProofSwarm swarm, CertificateChecker checker) = script.deploy(owner);
        assertEq(swarm.owner(), owner);
        assertTrue(swarm.owner() != address(script));
        assertEq(swarm.agentCount(), 0);
        assertEq(swarm.approvedBudget(), 0);
        assertEq(checker.MAX_COUNTED_VARIABLES(), 20);
    }

    function test_DeployRefusesTheZeroOwner() public {
        Deploy script = new Deploy();
        vm.expectRevert(ProofSwarm.ZeroAddress.selector);
        script.deploy(address(0));
    }

    function testFuzz_OwnerIsAlwaysTheArgument(address owner, address caller) public {
        vm.assume(owner != address(0));
        Deploy script = new Deploy();
        vm.prank(caller);
        (ProofSwarm swarm,) = script.deploy(owner);
        assertEq(swarm.owner(), owner);
    }
}
