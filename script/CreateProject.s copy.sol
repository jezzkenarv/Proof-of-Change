// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {ProofOfChange} from "../src/ProofOfChange.sol";
import {IProofOfChange} from "../src/Interfaces/IProofOfChange.sol";
import {IEAS, AttestationRequest, AttestationRequestData} from "@eas/IEAS.sol";
//import {MockEAS} from "../test/unit/ProofOfChangeTest.t.sol";

contract CreateProjectScript is Script {
    // Anvil's predefined accounts
    // address constant PROPOSER = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    // uint256 constant PROPOSER_KEY = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;

    // // Previously deployed contract addresses
    // address constant POC_ADDRESS = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512;
    // address constant EAS_ADDRESS = 0x5FbDB2315678afecb367f032d93F642f64180aa3;

    // function run() external returns (bool) {
    //     // Load addresses from environment
    //     address pocAddress = vm.envAddress("POC_ADDRESS");
    //     address easAddress = vm.envAddress("EAS_ADDRESS");
        
    //     vm.startBroadcast(PROPOSER_KEY);
        
    //     console.log("Using POC contract at:", pocAddress);
    //     console.log("Using EAS contract at:", easAddress);
    //     console.log("Proposer balance:", vm.toString(PROPOSER.balance));
        
    //     MockEAS eas = MockEAS(easAddress);
    //     bytes32 logbookUID = createMockAttestation(eas);
    //     console.log("Created mock attestation:", vm.toString(logbookUID));
        
    //     IProofOfChange poc = IProofOfChange(pocAddress);
        
    //     require(address(poc).code.length > 0, "POC contract not deployed");
        
    //     IProofOfChange.ProjectCreationData memory projectData = IProofOfChange.ProjectCreationData({
    //         duration: 90 days,
    //         requestedFunds: 10 ether,
    //         regionId: 1,
    //         logbookAttestationUID: logbookUID
    //     });

    //     console.log("Attempting to create project with:");
    //     console.log("- Duration:", vm.toString(projectData.duration));
    //     console.log("- Requested Funds:", vm.toString(projectData.requestedFunds));
    //     console.log("- Region ID:", vm.toString(projectData.regionId));
    //     console.log("- Logbook UID:", vm.toString(projectData.logbookAttestationUID));

    //     console.log("POC contract balance before:", vm.toString(address(poc).balance));
        
    //     bytes32 projectId = poc.createProject{value: 10 ether}(projectData);
    //     console.log("Project created with ID:", vm.toString(projectId));
        
    //     // Add multiple verification checks
    //     for (uint i = 0; i < 3; i++) {
    //         console.log("\nVerification attempt", i + 1);
    //         (
    //             address proposer,
    //             uint256 requestedFunds,
    //             uint256 duration,
    //             IProofOfChange.VoteType currentPhase,
    //             bytes32[] memory attestationUIDs
    //         ) = poc.getProjectDetails(projectId);
            
    //         console.log("Project details:");
    //         console.log("- Proposer:", proposer);
    //         console.log("- Requested Funds:", requestedFunds);
    //         console.log("- Duration:", duration);
    //         console.log("- Current Phase:", uint256(currentPhase));
            
    //         // Add a small delay between checks
    //         vm.roll(block.number + 1);
    //     }
        
    //     // Save project ID to a file that can be read by the voting script
    //     string[] memory inputs = new string[](3);
    //     inputs[0] = "echo";
    //     inputs[1] = vm.toString(projectId);
    //     inputs[2] = "> .lastProjectId";
    //     vm.ffi(inputs);
        
    //     vm.stopBroadcast();

    //     // Verify success conditions
    //     bool success = (
    //         address(poc).balance == 10 ether
    //     );
        
    //     console.log("Script completed successfully:", success);
    //     return success;
    // }

    // function createMockAttestation(MockEAS eas) internal returns (bytes32) {
    //     // Create attestation data
    //     bytes memory attestationData = abi.encode(
    //         uint256(block.timestamp),
    //         "Initial Project State",
    //         "Sample Location",
    //         "Initial satellite imagery showing project site"
    //     );

    //     AttestationRequest memory request = AttestationRequest({
    //         schema: eas.LOGBOOK_SCHEMA(),
    //         data: AttestationRequestData({
    //             recipient: address(0),
    //             expirationTime: 0,
    //             revocable: true,
    //             refUID: bytes32(0),
    //             data: attestationData,
    //             value: 0
    //         })
    //     });

    //     return eas.attest(request);
    // }
}