 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {ProofOfChange} from "../src/ProofOfChange.sol";

contract DeployProofOfChange is Script {
    function run() external {
        address easAddress = vm.envAddress("EAS_ADDRESS");
        
        // Create initial DAO members array
        address[] memory initialMembers = new address[](1);
        initialMembers[0] = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // Default anvil address
        
        vm.startBroadcast();
        
        ProofOfChange poc = new ProofOfChange(easAddress, initialMembers);
        console.log("ProofOfChange deployed at:", address(poc));
        
        vm.stopBroadcast();
    }
}