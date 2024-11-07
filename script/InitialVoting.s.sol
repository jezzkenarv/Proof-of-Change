// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;


import {Script, console} from "forge-std/Script.sol";
import {ProofOfChange} from "../src/ProofOfChange.sol";
import {IProofOfChange} from "../src/Interfaces/IProofOfChange.sol";

contract InitialVotingScript is Script {
    function run() external {
        address pocAddress = vm.envAddress("POC_ADDRESS");
        bytes32 projectId = vm.envBytes32("POC_PROJECT_ID");
        IProofOfChange poc = IProofOfChange(pocAddress);
        
        // DAO Member 1 votes
        uint256 daoKey1 = vm.envUint("DAO_KEY_1");
        vm.startBroadcast(daoKey1);
        (,,,, bytes32[] memory attestationUIDs) = poc.getProjectDetails(projectId);
        poc.vote(attestationUIDs[0], 1, true);
        vm.stopBroadcast();
        console.log("DAO Member 1 voted");
        
        // DAO Member 2 votes
        uint256 daoKey2 = vm.envUint("DAO_KEY_2");
        vm.startBroadcast(daoKey2);
        poc.vote(attestationUIDs[0], 1, true);
        vm.stopBroadcast();
        console.log("DAO Member 2 voted");
        
        // SubDAO Member 1 votes
        uint256 subDaoKey1 = vm.envUint("SUBDAO_KEY_1");
        vm.startBroadcast(subDaoKey1);
        poc.vote(attestationUIDs[0], 1, true);
        vm.stopBroadcast();
        console.log("SubDAO Member 1 voted");
        
        // SubDAO Member 2 votes
        uint256 subDaoKey2 = vm.envUint("SUBDAO_KEY_2");
        vm.startBroadcast(subDaoKey2);
        poc.vote(attestationUIDs[0], 1, true);
        vm.stopBroadcast();
        console.log("SubDAO Member 2 voted");
        
        // Proposer finalizes and advances
        uint256 proposerKey = vm.envUint("PROPOSER_KEY");
        vm.startBroadcast(proposerKey);
        poc.finalizeVote(attestationUIDs[0]);
        poc.advanceToNextPhase(projectId);
        console.log("Advanced to progress phase");
        vm.stopBroadcast();
    }
}