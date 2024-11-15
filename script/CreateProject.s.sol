// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {ProofOfChange} from "../src/ProofOfChange.sol";
import {IProofOfChange} from "../src/Interfaces/IProofOfChange.sol";
import {IEAS, AttestationRequest, AttestationRequestData} from "@eas/IEAS.sol";
//import {MockEAS} from "../test/unit/ProofOfChangeTest.t.sol";

contract CreateProjectScript is Script {
    // // Anvil's predefined accounts
    // address constant PROPOSER = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    // uint256 constant PROPOSER_KEY = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;

    // // Previously deployed contract addresses


    // function run() external {
    //     // Create mock attestation first
    //     vm.startBroadcast(PROPOSER_KEY);
    //     address POC_ADDRESS = vm.envAddress("POC_ADDRESS");
    //     address EAS_ADDRESS = vm.envAddress("EAS_ADDRESS");
        
    //     bytes32 logbookUID = vm.envBytes32("INITIAL_LOGBOOK_UID");
    //     MockEAS eas = MockEAS(EAS_ADDRESS);
    //     bytes32 mockAttestationUID = eas.createMockAttestation(PROPOSER, logbookUID);
    //     console.log("Created mock attestation:", vm.toString(mockAttestationUID));
        
    //     // Create project using the mock attestation
    //     IProofOfChange poc = IProofOfChange(POC_ADDRESS);
        
    //     IProofOfChange.ProjectCreationData memory projectData = IProofOfChange.ProjectCreationData({
    //         duration: 90 days,
    //         requestedFunds: 10 ether,
    //         regionId: 1,
    //         logbookAttestationUID: mockAttestationUID
    //     });

    //     bytes32 projectId = poc.createProject{value: 10 ether}(projectData);
    //     console.log("Project created with ID:", vm.toString(projectId));




    //     (
    //         address proposer,
    //         uint256 requestedFunds,
    //         uint256 duration,
    //         IProofOfChange.VoteType currentPhase,
    //         bytes32[] memory attestationUIDs
    //     ) = poc.getProjectDetails(projectId);
        
    //     console.log("\nProject details:");
    //     console.log("- Proposer:", proposer);
    //     console.log("- Requested Funds:", requestedFunds);
    //     console.log("- Duration:", duration);
    //     console.log("- Current Phase:", uint256(currentPhase));

    //     uint256 overallCompletion = poc.calculateOverallCompletion(projectId);
    //     console.log("Overall Completion:", overallCompletion);
        
    //     require(proposer != address(0), "Project does not exist");

    //     console.log("Voting for initial phase...");
    //     poc.vote(mockAttestationUID, 1, true);
    //     console.log("Voted for initial phase");

    //     vm.stopBroadcast();
    // }

    // // function createMockAttestation(MockEAS eas, bytes32 logbookUID) internal returns (bytes32) {
    // //     // Create attestation data
    // //     bytes memory attestationData = abi.encode(
    // //         uint256(block.timestamp),
    // //         "Initial Project State",
    // //         "Sample Location",
    // //         "Initial satellite imagery showing project site"
    // //     );

    // //     AttestationRequest memory request = AttestationRequest({
    // //         schema: eas.LOGBOOK_SCHEMA(),
    // //         data: AttestationRequestData({
    // //             recipient: address(0),
    // //             expirationTime: 0,
    // //             revocable: true,
    // //             refUID: logbookUID,
    // //             data: attestationData,
    // //             value: 0
    // //         })
    // //     });

    // //     return eas.attest(request);
    // // }
}