// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {ProofOfChange} from "../src/ProofOfChange.sol";
import {MockEAS} from "../test/unit/ProofOfChangeTest.t.sol";

contract ProofOfChangeScript is Script {
    // Anvil default account
    address constant ANVIL_ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 constant ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    
    function run() external {
        // Use Anvil's first account private key for local testing
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", ANVIL_PRIVATE_KEY);
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy MockEAS first
        MockEAS mockEAS = new MockEAS();
        console.log("MockEAS deployed to:", address(mockEAS));

        // Create initial DAO members array (using Anvil account as initial admin)
        address[] memory initialMembers = new address[](1);
        initialMembers[0] = ANVIL_ACCOUNT;

        // Deploy ProofOfChange contract with the actual MockEAS address
        ProofOfChange poc = new ProofOfChange(
            address(mockEAS),  // Use the actual deployed MockEAS address
            initialMembers     // Initial DAO members
        );

        vm.stopBroadcast();

        // Log the deployment
        console.log("ProofOfChange deployed to:", address(poc));
        console.log("Initial admin (Anvil Account):", ANVIL_ACCOUNT);
    }
}