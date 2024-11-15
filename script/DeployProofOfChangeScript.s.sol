// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {ProofOfChange} from "../src/ProofOfChange.sol";
// import {MockEAS} from "../test/unit/ProofOfChangeTest.t.sol";
import {IProofOfChange} from "../src/Interfaces/IProofOfChange.sol";

contract DeployProofOfChangeScript is Script {
    // // Anvil's first address (will be contract deployer & first DAO member)
    // address constant DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    // uint256 constant DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    
    // // Second Anvil address (will be second DAO member)
    // address constant DAO_MEMBER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;

    // function run() external {
    //     vm.startBroadcast(DEPLOYER_KEY);

    //     // Deploy MockEAS
    //     MockEAS mockEAS = new MockEAS();
    //     console.log("MockEAS deployed to:", address(mockEAS));

    //     // Setup initial DAO members
    //     address[] memory initialMembers = new address[](2);
    //     initialMembers[0] = DEPLOYER;
    //     initialMembers[1] = DAO_MEMBER;

    //     // Deploy ProofOfChange
    //     ProofOfChange poc = new ProofOfChange(
    //         address(mockEAS),
    //         initialMembers
    //     );
    //     console.log("ProofOfChange deployed to:", address(poc));

    //     vm.stopBroadcast();
    // }
}