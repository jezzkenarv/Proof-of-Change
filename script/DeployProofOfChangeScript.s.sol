// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {ProofOfChange} from "../src/ProofOfChange.sol";
import {MockEAS} from "../test/mocks/MockEAS.sol";

contract DeployProofOfChangeScript is Script {
    // Default voting period (7 days)
    uint256 constant VOTING_PERIOD = 7 days;

    function run() external returns (ProofOfChange, MockEAS) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy MockEAS first
        MockEAS mockEAS = new MockEAS();
        
        // Deploy ProofOfChange with mock EAS address
        ProofOfChange poc = new ProofOfChange(VOTING_PERIOD);
        
        // Setup initial state
        poc.addDAOMember(deployer);
        
        // Add a test SubDAO member (optional)
        poc.addSubDAOMember(deployer, 1); // Region ID 1
        
        vm.stopBroadcast();

        console.log("MockEAS deployed to:", address(mockEAS));
        console.log("ProofOfChange deployed to:", address(poc));
        
        return (poc, mockEAS);
    }
}