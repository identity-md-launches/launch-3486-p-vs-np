// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {ProofSwarm} from "../src/ProofSwarm.sol";
import {CertificateChecker} from "../src/CertificateChecker.sol";

/// @notice Deploys the two contracts. The owner is an argument, never the caller and never the environment:
///         forge script script/Deploy.s.sol --sig "run(address)" <owner>
/// @dev    This repository's job deploys nothing. The script is here to be reviewed and run by the owner.
contract Deploy is Script {
    function run(address owner_) external returns (ProofSwarm swarm, CertificateChecker checker) {
        vm.startBroadcast();
        (swarm, checker) = deploy(owner_);
        vm.stopBroadcast();
    }

    function deploy(address owner_) public returns (ProofSwarm swarm, CertificateChecker checker) {
        swarm = new ProofSwarm(owner_);
        checker = new CertificateChecker();
    }
}
