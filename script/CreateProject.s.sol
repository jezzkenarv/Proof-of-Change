// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;


import {Script, console} from "forge-std/Script.sol";
import {ProofOfChange} from "../src/ProofOfChange.sol";
import {IProofOfChange} from "../src/Interfaces/IProofOfChange.sol";

contract CreateProjectScript is Script {
    function run() external {
        // Load environment variables
        uint256 proposerKey = vm.envUint("PROPOSER_KEY");
        address pocAddress = vm.envAddress("POC_ADDRESS");
        bytes32 logbookUID = vm.envBytes32("INITIAL_LOGBOOK_UID");
        
        IProofOfChange poc = IProofOfChange(pocAddress);
        
        vm.startBroadcast(proposerKey);
        
        // Create project with Logbook attestation
        IProofOfChange.ProjectCreationData memory projectData = IProofOfChange.ProjectCreationData({
            duration: 90 days,
            requestedFunds: 10 ether,
            regionId: 1,
            logbookAttestationUID: logbookUID
        });
        
        bytes32 projectId = poc.createProject{value: 10 ether}(projectData);
        console.log("Project created with ID:", uint256(projectId));
        
        // Save project ID to file for future scripts
        string memory projectInfo = string(abi.encodePacked(
            "POC_PROJECT_ID=", vm.toString(projectId)
        ));
        vm.writeFile(".env.project", projectInfo);
        
        vm.stopBroadcast();
    }
}