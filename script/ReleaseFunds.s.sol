// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;


import {Script, console} from "forge-std/Script.sol";
import {ProofOfChange} from "../src/ProofOfChange.sol";
import {IProofOfChange} from "../src/Interfaces/IProofOfChange.sol";

contract ReleaseFundsScript is Script {
    function run() external {
        address pocAddress = vm.envAddress("POC_ADDRESS");
        bytes32 projectId = vm.envBytes32("POC_PROJECT_ID");
        IProofOfChange poc = IProofOfChange(pocAddress);
        
        uint256 daoKey = vm.envUint("DAO_KEY_1");
        vm.startBroadcast(daoKey);
        
        poc.releasePhaseFunds(projectId, IProofOfChange.VoteType.Initial);
        poc.releasePhaseFunds(projectId, IProofOfChange.VoteType.Progress);
        poc.releasePhaseFunds(projectId, IProofOfChange.VoteType.Completion);
        
        console.log("All funds released");
        vm.stopBroadcast();
    }
}