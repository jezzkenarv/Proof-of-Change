// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Script demonstrates:
// Contract deployment and initial setup
// Project creation with funds
// Complete lifecycle through all phases:
//      Initial phase with voting and fund release
//      Progress phase with updates and voting
//      Completion phase and final status update
// Interaction between DAO and SubDAO members
// Fund distribution at each phase
// Proper attestation handling

import {Script, console} from "forge-std/Script.sol";
import {ProofOfChange} from "../src/ProofOfChange.sol";
import {MockEAS} from "../test/unit/ProofOfChangeTest.t.sol";
import {IProofOfChange} from "../src/interfaces/IProofOfChange.sol";
import {IEAS, Attestation, AttestationRequest, AttestationRequestData} from "@eas/IEAS.sol";
import "@eas/Common.sol";

contract ProofOfChangeScript is Script {
    // Anvil default accounts
    address constant ANVIL_ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address constant SUBDAO_MEMBER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    uint256 constant ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 constant SUBDAO_PRIVATE_KEY = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;

    // Contract instances
    IProofOfChange poc;
    MockEAS mockEAS;

    // Project tracking
    bytes32 public projectId;
    bytes32 public initialAttestationUID;
    bytes32 public progressAttestationUID;
    bytes32 public completionAttestationUID;

    // Add with other constants
    bytes32 constant LOGBOOK_SCHEMA = 0xb16fa048b0d597f5a821747eba64efa4762ee5143e9a80600d0005386edfc995;

    // Add this to store deployed contract addresses
    address public deployedMockEAS;
    address public deployedProofOfChange;

    // Add these events at the contract level
    event DeploymentSaved(
        address mockEAS,
        address proofOfChange,
        bytes32 projectId
    );

    // Add these constants at the contract level
    uint256 constant VOTING_PERIOD = 7 days;
    uint256 constant BUFFER_TIME = 1 hours;

    function run() external {
        // Check if we're in simulation mode
        bool isSimulation = vm.envOr("SIMULATION", false);
        
        if (!isSimulation) {
            // Deployment mode
            deployContracts();
            setupDemo();
            createProjectDemo();
            initialPhaseDemo();
            progressPhaseDemo();
            completionPhaseDemo();
            
            // Save deployment state
            saveDeployment();
        } else {
            // Load previous deployment
            loadDeployment();
            console.log("\nLoaded deployment state:");
            console.log("MockEAS:", deployedMockEAS);
            console.log("ProofOfChange:", deployedProofOfChange);
            console.log("Project ID:", uint256(projectId));
            
            // Initialize contract instances
            mockEAS = MockEAS(deployedMockEAS);
            poc = IProofOfChange(deployedProofOfChange);
            
            // Log initial project state
            logProjectState(projectId);
            
            // Run through project lifecycle
            initialPhaseDemo();
            progressPhaseDemo();
            completionPhaseDemo();
        }
    }

    function deployContracts() internal {
        vm.startBroadcast(ANVIL_PRIVATE_KEY);

        // Deploy MockEAS
        mockEAS = new MockEAS();
        deployedMockEAS = address(mockEAS);
        console.log("MockEAS deployed to:", deployedMockEAS);

        // Setup initial DAO members
        address[] memory initialMembers = new address[](1);
        initialMembers[0] = ANVIL_ACCOUNT;

        // Deploy ProofOfChange and cast to interface
        poc = IProofOfChange(
            address(new ProofOfChange(
                address(mockEAS),
                initialMembers
            ))
        );
        deployedProofOfChange = address(poc);

        vm.stopBroadcast();
        console.log("ProofOfChange deployed to:", deployedProofOfChange);
    }

    function setupDemo() internal {
        vm.startBroadcast(ANVIL_PRIVATE_KEY);

        // Add SubDAO member
        poc.addSubDAOMember(SUBDAO_MEMBER, 1); // Region ID 1
        console.log("Added SubDAO member:", SUBDAO_MEMBER);

        vm.stopBroadcast();
    }

    function createProjectDemo() internal {
        vm.startBroadcast(ANVIL_PRIVATE_KEY);

        // Create mock attestation for project creation
        AttestationRequest memory request = AttestationRequest({
            schema: LOGBOOK_SCHEMA,
            data: AttestationRequestData({
                recipient: address(0),
                expirationTime: 0,
                revocable: true,
                refUID: bytes32(0),
                data: abi.encode(""),
                value: 0
            })
        });
        initialAttestationUID = mockEAS.attest(request);
        console.log("Created initial attestation:", uint256(initialAttestationUID));

        // Create project using the interface's struct type
        IProofOfChange.ProjectCreationData memory projectData = IProofOfChange.ProjectCreationData({
            duration: 30 days,
            requestedFunds: 1 ether,
            regionId: 1,
            logbookAttestationUID: initialAttestationUID
        });

        projectId = poc.createProject{value: 1 ether}(projectData);
        console.log("Created project with ID:", uint256(projectId));
        
        vm.stopBroadcast();
    }

    function initialPhaseDemo() internal {
        console.log("\nStarting initial phase for project:", uint256(projectId));
        console.log("Current timestamp:", block.timestamp);
        
        vm.startBroadcast(ANVIL_PRIVATE_KEY);
        
        // Create initial phase attestation
        bytes32 attestationUID = poc.createPhaseAttestation(
            projectId,
            IProofOfChange.VoteType.Initial
        );
        console.log("Created initial phase attestation:", uint256(attestationUID));
        
        // Vote on initial phase
        poc.vote(attestationUID, 1, true);
        console.log("DAO member voted on initial phase");
        
        vm.stopBroadcast();
        
        vm.startBroadcast(SUBDAO_PRIVATE_KEY);
        poc.vote(attestationUID, 1, true);
        console.log("SubDAO member voted on initial phase");
        vm.stopBroadcast();
        
        // Wait for voting period with buffer
        uint256 votingPeriod = 7 days;
        vm.warp(block.timestamp + votingPeriod + 1 hours);
        console.log("Warped to timestamp for initial vote:", block.timestamp);
        
        vm.startBroadcast(ANVIL_PRIVATE_KEY);
        
        // Finalize initial phase vote
        poc.finalizeVote(attestationUID);
        console.log("Finalized initial phase vote");
        
        // Add small buffer before advancing phase
        vm.warp(block.timestamp + 1 hours);
        console.log("Warped to timestamp for phase advance:", block.timestamp);
        
        // Advance to progress phase
        poc.advanceToNextPhase(projectId);
        console.log("Advanced to progress phase");
        
        vm.stopBroadcast();
    }

    function progressPhaseDemo() internal {
        console.log("Starting progress phase at timestamp:", block.timestamp);
        verifyProjectPhase(projectId, 1); // Verify we're in progress phase (1)
        
        vm.startBroadcast(ANVIL_PRIVATE_KEY);
        
        // Create progress attestation
        progressAttestationUID = mockEAS.attest(
            AttestationRequest({
                schema: LOGBOOK_SCHEMA,
                data: AttestationRequestData({
                    recipient: address(0),
                    expirationTime: 0,
                    revocable: true,
                    refUID: bytes32(0),
                    data: abi.encode(""),
                    value: 0
                })
            })
        );
        console.log("Created progress attestation:", uint256(progressAttestationUID));

        // Submit progress update
        poc.submitProgress(projectId, progressAttestationUID);
        console.log("Submitted progress update");

        // Create phase attestation for progress phase
        bytes32 attestationUID = poc.createPhaseAttestation(
            projectId,
            IProofOfChange.VoteType.Progress
        );
        console.log("Created progress phase attestation:", uint256(attestationUID));

        // DAO member votes
        poc.vote(attestationUID, 1, true);
        console.log("DAO member voted on progress phase");
        vm.stopBroadcast();

        // SubDAO member votes
        vm.startBroadcast(SUBDAO_PRIVATE_KEY);
        poc.vote(attestationUID, 1, true);
        console.log("SubDAO member voted on progress phase");
        vm.stopBroadcast();

        // Wait for voting period with buffer
        uint256 votingPeriod = 7 days;
        vm.warp(block.timestamp + votingPeriod + 1 hours);
        console.log("Warped to timestamp:", block.timestamp);

        vm.startBroadcast(ANVIL_PRIVATE_KEY);
        // Finalize vote
        poc.finalizeVote(attestationUID);
        console.log("Finalized progress phase vote");
        
        // Advance to completion phase
        poc.advanceToNextPhase(projectId);
        console.log("Advanced to completion phase");
        vm.stopBroadcast();
    }

    function completionPhaseDemo() internal {
        console.log("Starting completion phase at timestamp:", block.timestamp);
        verifyProjectPhase(projectId, 2); // Verify we're in completion phase (2)
        
        vm.startBroadcast(ANVIL_PRIVATE_KEY);
        
        // Create completion attestation
        completionAttestationUID = mockEAS.attest(
            AttestationRequest({
                schema: LOGBOOK_SCHEMA,
                data: AttestationRequestData({
                    recipient: address(0),
                    expirationTime: 0,
                    revocable: true,
                    refUID: bytes32(0),
                    data: abi.encode(""),
                    value: 0
                })
            })
        );
        console.log("Created completion attestation:", uint256(completionAttestationUID));

        // Submit completion update
        poc.submitCompletion(projectId, completionAttestationUID);
        console.log("Submitted completion update");

        // Create completion phase attestation
        bytes32 attestationUID = poc.createPhaseAttestation(
            projectId,
            IProofOfChange.VoteType.Completion
        );
        console.log("Created completion phase attestation:", uint256(attestationUID));

        // Vote on completion phase
        poc.vote(attestationUID, 1, true);
        console.log("DAO member voted on completion phase");
        vm.stopBroadcast();

        // SubDAO member votes
        vm.startBroadcast(SUBDAO_PRIVATE_KEY);
        poc.vote(attestationUID, 1, true);
        console.log("SubDAO member voted on completion phase");
        vm.stopBroadcast();

        // Wait for voting period with buffer
        uint256 votingPeriod = 7 days;
        vm.warp(block.timestamp + votingPeriod + 1 hours);
        console.log("Warped to timestamp for completion vote:", block.timestamp);

        vm.startBroadcast(ANVIL_PRIVATE_KEY);
        // Finalize vote
        poc.finalizeVote(attestationUID);
        console.log("Finalized completion phase vote");

        // Add small buffer before marking complete
        vm.warp(block.timestamp + 1 hours);
        console.log("Warped to timestamp for completion:", block.timestamp);

        // Mark project as complete
        poc.markProjectAsComplete(projectId);
        console.log("Project marked as complete");

        // Add small buffer before fund release
        vm.warp(block.timestamp + 1 hours);
        console.log("Warped to timestamp for fund release:", block.timestamp);

        // Release funds for all phases
        poc.releasePhaseFunds(projectId, IProofOfChange.VoteType.Initial);
        console.log("Released initial phase funds");
        
        poc.releasePhaseFunds(projectId, IProofOfChange.VoteType.Progress);
        console.log("Released progress phase funds");
        
        poc.releasePhaseFunds(projectId, IProofOfChange.VoteType.Completion);
        console.log("Released completion phase funds");

        vm.stopBroadcast();
    }

    // Add this helper function
    function verifyProjectPhase(bytes32 _projectId, uint256 expectedPhase) internal view {
        (,,,IProofOfChange.VoteType currentPhase,) = poc.getProjectDetails(_projectId);
        uint256 currentPhaseNum = uint256(currentPhase);
        require(currentPhaseNum == expectedPhase, string.concat("Wrong phase. Expected: ", vm.toString(expectedPhase), " Got: ", vm.toString(currentPhaseNum)));
        console.log("Verified project is in phase:", currentPhaseNum);
    }

    function logProjectState(bytes32 _projectId) internal view {
        (
            address proposer,
            uint256 requestedFunds,
            uint256 duration,
            IProofOfChange.VoteType currentPhase,
            bytes32[] memory attestationUIDs
        ) = poc.getProjectDetails(_projectId);
        
        console.log("\nProject State:");
        console.log("Proposer:", proposer);
        console.log("Requested Funds:", requestedFunds);
        console.log("Duration:", duration);
        console.log("Current Phase:", uint256(currentPhase));
        console.log("Number of attestations:", attestationUIDs.length);
    }

    // Replace saveDeployment function
    function saveDeployment() internal {
        emit DeploymentSaved(
            deployedMockEAS,
            deployedProofOfChange,
            projectId
        );
        
        console.log("\nSaving deployment state:");
        console.log("MockEAS:", deployedMockEAS);
        console.log("ProofOfChange:", deployedProofOfChange);
        console.log("Project ID (hex):", vm.toString(bytes32(projectId)));
        console.log("Project ID (uint):", uint256(projectId));
    }

    // Update loadDeployment function to use constructor parameters or hardcoded values
    function loadDeployment() internal {
        // Use constructor parameters or hardcoded values for testing
        deployedMockEAS = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;
        deployedProofOfChange = 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9;
        projectId = 0xbe337491a3b8f015b1f308c501c402985f4fe26ed84fa44b8bf57d2830dfe05e;
        
        console.log("\nLoaded deployment state:");
        console.log("MockEAS:", deployedMockEAS);
        console.log("ProofOfChange:", deployedProofOfChange);
        console.log("Project ID (hex):", vm.toString(bytes32(projectId)));
        console.log("Project ID (uint):", uint256(projectId));
    }
}