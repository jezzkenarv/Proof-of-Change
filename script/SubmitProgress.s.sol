// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;


import {Script, console} from "forge-std/Script.sol";
import {ProofOfChange} from "../src/ProofOfChange.sol";
import {IProofOfChange} from "../src/Interfaces/IProofOfChange.sol";

contract SubmitProgressScript is Script {
    // function run() external {
    //     address pocAddress = vm.envAddress("POC_ADDRESS");
    //     bytes32 projectId = vm.envBytes32("POC_PROJECT_ID");
    //     bytes32 progressLogbookUID = vm.envBytes32("PROGRESS_LOGBOOK_UID");
    //     IProofOfChange poc = IProofOfChange(pocAddress);
        
    //     uint256 proposerKey = vm.envUint("PROPOSER_KEY");
    //     vm.startBroadcast(proposerKey);
        
    //     // Submit progress with new Logbook attestation
    //     poc.submitProgress(projectId, progressLogbookUID);
    //     bytes32 progressPhaseUID = poc.createPhaseAttestation(
    //         projectId,
    //         IProofOfChange.VoteType.Progress
    //     );
    //     console.log("Progress submitted with attestation:", uint256(progressPhaseUID));
        
    //     vm.stopBroadcast();
    // }
}