// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {IProofOfChange} from "../src/Interfaces/IProofOfChange.sol";

contract InitialVotingScript is Script {
    // Anvil addresses
    address constant DAO_MEMBER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address constant SUBDAO_MEMBER = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;
    
    // Anvil private keys
    uint256 constant DAO_KEY = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 constant SUBDAO_KEY_1 = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;

    function run() external {
        address pocAddress = vm.envAddress("POC_ADDRESS");
        bytes32 projectId = vm.envBytes32("POC_PROJECT_ID");
        bytes32 initialLogbookUid = vm.envBytes32("INITIAL_LOGBOOK_UID");
        
        console.log("\nContract Information:");
        console.log("POC Address:", pocAddress);
        console.log("Project ID (hex):", vm.toString(projectId));
        console.log("Initial Logbook UID (hex):", vm.toString(initialLogbookUid));
        
        IProofOfChange poc = IProofOfChange(pocAddress);
        
        // Get project details
        (
            address proposer,
            uint256 requestedFunds,
            uint256 duration,
            IProofOfChange.VoteType currentPhase,
            bytes32[] memory attestationUIDs
        ) = poc.getProjectDetails(projectId);
        
        console.log("\nProject details:");
        console.log("- Proposer:", proposer);
        console.log("- Requested Funds:", requestedFunds);
        console.log("- Duration:", duration);
        console.log("- Current Phase:", uint256(currentPhase));

        uint256 overallCompletion = poc.calculateOverallCompletion(projectId);
        console.log("Overall Completion:", overallCompletion);
        
        require(proposer != address(0), "Project does not exist");
        
        vm.startBroadcast();
        poc.vote(initialLogbookUid, 1, true);
        vm.stopBroadcast();
    }
}