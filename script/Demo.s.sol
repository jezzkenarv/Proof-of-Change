// deploy poc
// create project
// display project details

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {ProofOfChange} from "../src/ProofOfChange.sol";
import {MockEAS} from "../test/unit/ProofOfChangeTest.t.sol";
import {IProofOfChange} from "../src/Interfaces/IProofOfChange.sol";

contract DemoScript is Script {
    // Anvil's first address (will be contract deployer & first DAO member)
    address constant DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 constant DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address constant PROPOSER = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    uint256 constant PROPOSER_KEY = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;

    // Second Anvil address (will be second DAO member)
    address constant DAO_MEMBER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;

    function run() external {
        vm.startBroadcast(DEPLOYER_KEY);

        // Deploy MockEAS
        MockEAS eas = new MockEAS();
        console.log("MockEAS deployed to:", address(eas));

        // Setup initial DAO members
        address[] memory initialMembers = new address[](2);
        initialMembers[0] = DEPLOYER;
        initialMembers[1] = DAO_MEMBER;

        // Deploy ProofOfChange
        ProofOfChange poc = new ProofOfChange(address(eas), initialMembers);
        console.log("ProofOfChange deployed to:", address(poc));

        bytes32 logbookUID = vm.envBytes32("INITIAL_LOGBOOK_UID");
        bytes32 mockAttestationUID = eas.createMockAttestation(PROPOSER, logbookUID);
        console.log("Created mock attestation:", vm.toString(mockAttestationUID));

        IProofOfChange.ProjectCreationData memory projectData = IProofOfChange.ProjectCreationData({
            duration: 90 days,
            requestedFunds: 10 ether,
            regionId: 1,
            logbookAttestationUID: mockAttestationUID
        });

        vm.stopBroadcast();
        vm.startBroadcast(PROPOSER_KEY);

        bytes32 projectId = poc.createProject{value: 10 ether}(projectData);
        console.log("Project created with ID:", vm.toString(projectId));

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


        vm.stopBroadcast();
    }
}
