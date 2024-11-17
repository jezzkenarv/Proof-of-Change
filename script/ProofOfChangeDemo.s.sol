// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {ProofOfChange} from "../src/ProofOfChange.sol";
import {MockEAS} from "../test/mocks/MockEAS.sol";

contract ProofOfChangeDemo is Script {
    // Contract instances
    ProofOfChange poc;
    MockEAS mockEAS;

    // Test accounts
    address constant ADMIN = address(1);
    address constant PROPOSER = address(2);
    address constant DAO_MEMBER = address(3);
    address constant SUBDAO_MEMBER = address(4);

    // Logbook Schema and Data Format
    bytes32 constant LOGBOOK_SCHEMA = 0xba4171c92572b1e4f241d044c32cdf083be9fd946b8766977558ca6378c824e2;
    string constant LOCATION_COORDINATES = "-122.048, 37.0084";
    uint256 constant EVENT_TIMESTAMP = 1730958222;
    string constant IPFS_HASH = "QmPXWfoM9tbg4RvJh9NwF6dmrFPMK5xe5RwWuUEqHWM8t7";
    bytes32 constant IMAGE_HASH = keccak256(abi.encodePacked(IPFS_HASH));

    // Project tracking
    bytes32 public projectId;
    mapping(uint8 => bytes32) public attestationUIDs;
    mapping(uint8 => bytes32) public imageHashes;

    // Configuration
    uint256 constant VOTING_PERIOD = 7 days;
    uint256 constant PROJECT_FUNDS = 1 ether;
    uint256 constant PROJECT_DURATION = 90 days;
    uint256 constant REGION_ID = 1;

    function setUp() public {
        // Set gas price to 0 for all transactions
        vm.txGasPrice(0);
        
        // Fund accounts with much more ETH
        vm.deal(ADMIN, 1000 ether);
        vm.deal(PROPOSER, 1000 ether);
        vm.deal(DAO_MEMBER, 1000 ether);
        vm.deal(SUBDAO_MEMBER, 1000 ether);

        // Also fund the zero address and other potential sender addresses
        vm.deal(address(0), 1000 ether);
        vm.deal(0x0000000000000000000000000000000000000001, 1000 ether);
    }

    function run() public {
        setUp();

        // Deploy contracts
        deployContracts();
        
        // Setup roles
        setupRoles();
        
        // Run through project lifecycle
        createProject();
        console.log("\nProject created with ID:", uint256(projectId));
        console.log("Using mock Logbook schema:", uint256(LOGBOOK_SCHEMA));
        console.log("Location:", LOCATION_COORDINATES);
        console.log("IPFS Hash:", IPFS_HASH);
        
        runInitialPhase();
        console.log("\nInitial phase completed");
        
        runProgressPhase();
        console.log("\nProgress phase completed");
        
        runCompletionPhase();
        console.log("\nCompletion phase completed");
        
        // Print final status
        printProjectStatus();
    }

    function deployContracts() internal {
        // Set gas price to 0 before each broadcast
        vm.txGasPrice(0);
        vm.startBroadcast(ADMIN);
        
        // Deploy MockEAS
        mockEAS = new MockEAS();
        console.log("MockEAS deployed to:", address(mockEAS));

        // Deploy ProofOfChange and set ADMIN as the owner
        poc = new ProofOfChange(VOTING_PERIOD);
        console.log("ProofOfChange deployed to:", address(poc));

        vm.stopBroadcast();
    }

    function setupRoles() internal {
        vm.startBroadcast(ADMIN);

        // Add DAO and SubDAO members
        poc.addDAOMember(DAO_MEMBER);
        poc.addSubDAOMember(SUBDAO_MEMBER, REGION_ID);

        vm.stopBroadcast();
        console.log("Roles configured");
    }

    function createProject() internal {
        vm.startBroadcast(PROPOSER);
        
        // Create mock attestation with real Logbook data format
        bytes memory attestationData = abi.encode(
            EVENT_TIMESTAMP,
            LOCATION_COORDINATES,
            "Initial state attestation"
        );

        MockEAS.AttestationRequest memory request = MockEAS.AttestationRequest({
            schema: LOGBOOK_SCHEMA,
            recipient: PROPOSER,
            expirationTime: uint64(block.timestamp + 365 days),
            revocable: true,
            refUID: bytes32(0),
            data: attestationData,
            value: 0
        });

        // Create attestation using MockEAS
        attestationUIDs[0] = mockEAS.attest(request);
        imageHashes[0] = IMAGE_HASH;

        // Create project
        projectId = poc.createProject{value: PROJECT_FUNDS}(
            attestationUIDs[0],
            imageHashes[0],
            LOCATION_COORDINATES,
            PROJECT_FUNDS,
            REGION_ID,
            PROJECT_DURATION
        );

        vm.stopBroadcast();
    }

    function runInitialPhase() internal {
        // Start voting
        vm.startBroadcast(PROPOSER);
        poc.startVoting(projectId);
        vm.stopBroadcast();
        console.log("Initial voting started");

        // Cast votes
        vm.startBroadcast(DAO_MEMBER);
        poc.castVote(projectId, true);
        vm.stopBroadcast();

        vm.startBroadcast(SUBDAO_MEMBER);
        poc.castVote(projectId, true);
        vm.stopBroadcast();
        console.log("Votes cast for initial phase");

        // Warp time to end voting period
        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        // Finalize voting
        vm.startBroadcast(PROPOSER);
        poc.finalizeVoting(projectId);
        vm.stopBroadcast();
    }

    function runProgressPhase() internal {
        vm.startBroadcast(PROPOSER);
        
        // Create progress attestation
        bytes memory progressData = abi.encode(
            block.timestamp,
            LOCATION_COORDINATES,
            "Progress update attestation"
        );

        MockEAS.AttestationRequest memory request = MockEAS.AttestationRequest({
            schema: LOGBOOK_SCHEMA,
            recipient: PROPOSER,
            expirationTime: uint64(block.timestamp + 365 days),
            revocable: true,
            refUID: attestationUIDs[0], // Reference initial attestation
            data: progressData,
            value: 0
        });
        
        attestationUIDs[1] = mockEAS.attest(request);
        imageHashes[1] = keccak256(abi.encodePacked(IPFS_HASH, "_progress"));

        // Submit progress state proof
        poc.submitStateProof(
            projectId,
            attestationUIDs[1],
            imageHashes[1]
        );

        // Start voting
        poc.startVoting(projectId);
        vm.stopBroadcast();
        console.log("Progress phase started");

        // Cast votes
        vm.startBroadcast(DAO_MEMBER);
        poc.castVote(projectId, true);
        vm.stopBroadcast();

        vm.startBroadcast(SUBDAO_MEMBER);
        poc.castVote(projectId, true);
        vm.stopBroadcast();
        console.log("Votes cast for progress phase");

        // Warp time
        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        // Finalize
        vm.startBroadcast(PROPOSER);
        poc.finalizeVoting(projectId);
        vm.stopBroadcast();
    }

    function runCompletionPhase() internal {
        vm.startBroadcast(PROPOSER);
        
        // Create completion attestation
        bytes memory completionData = abi.encode(
            block.timestamp,
            LOCATION_COORDINATES,
            "Completion attestation"
        );

        MockEAS.AttestationRequest memory request = MockEAS.AttestationRequest({
            schema: LOGBOOK_SCHEMA,
            recipient: PROPOSER,
            expirationTime: uint64(block.timestamp + 365 days),
            revocable: true,
            refUID: attestationUIDs[1], // Reference progress attestation
            data: completionData,
            value: 0
        });
        
        attestationUIDs[2] = mockEAS.attest(request);
        imageHashes[2] = keccak256(abi.encodePacked(IPFS_HASH, "_completion"));

        // Submit completion state proof
        poc.submitStateProof(
            projectId,
            attestationUIDs[2],
            imageHashes[2]
        );

        // Start voting
        poc.startVoting(projectId);
        vm.stopBroadcast();
        console.log("Completion phase started");

        // Cast votes
        vm.startBroadcast(DAO_MEMBER);
        poc.castVote(projectId, true);
        vm.stopBroadcast();

        vm.startBroadcast(SUBDAO_MEMBER);
        poc.castVote(projectId, true);
        vm.stopBroadcast();
        console.log("Votes cast for completion phase");

        // Warp time
        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        // Finalize
        vm.startBroadcast(PROPOSER);
        poc.finalizeVoting(projectId);
        vm.stopBroadcast();
    }

    function printProjectStatus() internal view {
        // Get final project details
        ProofOfChange.ProjectDetails memory details = poc.getProjectDetails(projectId);

        console.log("\nFinal Project Status:");
        console.log("--------------------");
        console.log("Proposer:", details.proposer);
        console.log("Location:", details.location);
        console.log("Requested Funds:", details.requestedFunds);
        console.log("Region ID:", details.regionId);
        console.log("Duration:", details.estimatedDuration);
        console.log("Start Time:", details.startTime);
        console.log("Elapsed Time:", details.elapsedTime);
        console.log("Remaining Time:", details.remainingTime);
        console.log("Is Active:", details.isActive);
        console.log("Current Phase:", details.currentPhase);

        // Print state proofs
        for (uint8 i = 0; i < 3; i++) {
            (
                bytes32 attestationUID,
                bytes32 imageHash,
                uint256 timestamp,
                bool completed
            ) = poc.getStateProofDetails(projectId, i);

            console.log(string.concat("\nPhase ", vm.toString(i), " State Proof:"));
            console.log("Attestation UID:", uint256(attestationUID));
            console.log("Image Hash:", uint256(imageHash));
            console.log("Timestamp:", timestamp);
            console.log("Completed:", completed);
        }

        // Print contract balance
        console.log("\nContract Balance:", poc.getContractBalance());
    }
}