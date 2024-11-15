// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;


import {Script, console} from "forge-std/Script.sol";
import {ProofOfChange} from "../src/ProofOfChange.sol";
import {IProofOfChange} from "../src/Interfaces/IProofOfChange.sol";

contract SubmitCompletionScript is Script {
    // function run() external {
    //     address pocAddress = vm.envAddress("POC_ADDRESS");
    //     bytes32 projectId = vm.envBytes32("POC_PROJECT_ID");
    //     bytes32 completionLogbookUID = vm.envBytes32("COMPLETION_LOGBOOK_UID");
    //     IProofOfChange poc = IProofOfChange(pocAddress);
        
    //     uint256 proposerKey = vm.envUint("PROPOSER_KEY");
    //     vm.startBroadcast(proposerKey);
        
    //     poc.submitCompletion(projectId, completionLogbookUID);
    //     bytes32 completionPhaseUID = poc.createPhaseAttestation(
    //         projectId,
    //         IProofOfChange.VoteType.Completion
    //     );
    //     console.log("Completion submitted with attestation:", uint256(completionPhaseUID));
        
    //     vm.stopBroadcast();
    // }
}