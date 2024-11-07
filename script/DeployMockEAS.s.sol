// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {MockEAS} from "../test/unit/ProofOfChangeTest.t.sol";

contract DeployMockEAS is Script {
    function run() external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        MockEAS mockEAS = new MockEAS();
        console.log("MockEAS deployed at:", address(mockEAS));
        
        vm.stopBroadcast();
        return address(mockEAS);
    }
} 