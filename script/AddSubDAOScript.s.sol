// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {IProofOfChange} from "../src/Interfaces/IProofOfChange.sol";

contract AddSubDAOScript is Script {
    // Anvil addresses for SubDAO members
    address constant SUBDAO_1 = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;
    address constant SUBDAO_2 = 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65;
    uint256 constant DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function run() external {
        // Load POC address from environment
        address pocAddress = address(0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512); // Your deployed address
        IProofOfChange poc = IProofOfChange(pocAddress);

        vm.startBroadcast(DEPLOYER_KEY);

        // Add SubDAO members
        poc.addSubDAOMember(SUBDAO_1, 1);
        poc.addSubDAOMember(SUBDAO_2, 1);
        
        console.log("Added SubDAO members:");
        console.log("SubDAO 1:", SUBDAO_1);
        console.log("SubDAO 2:", SUBDAO_2);

        vm.stopBroadcast();
    }
}