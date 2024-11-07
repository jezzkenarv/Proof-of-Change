// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {IProofOfChange} from "../src/Interfaces/IProofOfChange.sol";
import {IEAS, AttestationRequest, AttestationRequestData} from "@eas/IEAS.sol";
import {MockEAS, Attestation} from "../test/unit/ProofOfChangeTest.t.sol";

contract CreateAndVoteScript is Script {
    address constant PROPOSER = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    uint256 constant PROPOSER_KEY = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    
    function run() external {
        console.log("Script started");
        
        address pocAddress = vm.envAddress("POC_ADDRESS");
        address easAddress = vm.envAddress("EAS_ADDRESS");
        
        console.log("Using POC contract at:", pocAddress);
        console.log("Using EAS contract at:", easAddress);
        
        uint256 balanceBefore = address(PROPOSER).balance;
        console.log("Proposer balance before:", balanceBefore);
        
        vm.startBroadcast(PROPOSER_KEY);
        console.log("Broadcast started");
        
        try MockEAS(easAddress).createMockAttestation(PROPOSER) returns (bytes32 logbookUID) {
            console.log("Created mock attestation:", vm.toString(logbookUID));
            
            try MockEAS(easAddress).getAttestation(logbookUID) returns (Attestation memory att) {
                console.log("Attestation verified:");
                console.log(" - Schema:", vm.toString(att.schema));
                console.log(" - Attester:", att.attester);
                
                IProofOfChange.ProjectCreationData memory projectData = IProofOfChange.ProjectCreationData({
                    duration: 90 days,
                    requestedFunds: 10 ether,
                    regionId: 1,
                    logbookAttestationUID: logbookUID
                });

                console.log("Attempting to create project...");
                
                try IProofOfChange(pocAddress).createProject{value: 10 ether}(projectData) returns (bytes32 projectId) {
                    console.log("Project created with ID:", vm.toString(projectId));
                    
                    try IProofOfChange(pocAddress).createPhaseAttestation(
                        projectId,
                        IProofOfChange.VoteType.Initial
                    ) returns (bytes32 phaseAttestationUID) {
                        console.log("Created phase attestation:", vm.toString(phaseAttestationUID));
                    } catch Error(string memory reason) {
                        console.log("Phase attestation creation failed:", reason);
                    } catch (bytes memory) {
                        console.log("Phase attestation creation failed with no reason");
                    }
                } catch Error(string memory reason) {
                    console.log("Project creation failed:", reason);
                } catch (bytes memory) {
                    console.log("Project creation failed with no reason");
                }
            } catch Error(string memory reason) {
                console.log("Attestation verification failed:", reason);
            } catch (bytes memory) {
                console.log("Attestation verification failed with no reason");
            }
        } catch Error(string memory reason) {
            console.log("Mock attestation creation failed:", reason);
        } catch (bytes memory) {
            console.log("Mock attestation creation failed with no reason");
        }

        vm.stopBroadcast();
        console.log("Broadcast stopped");
        
        uint256 balanceAfter = address(PROPOSER).balance;
        console.log("ETH spent:", balanceBefore - balanceAfter);
    }
}