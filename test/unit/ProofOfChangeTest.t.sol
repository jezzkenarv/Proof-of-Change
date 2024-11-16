// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {ProofOfChange} from "../../src/ProofOfChange.sol";
import {IProofOfChange} from "../../src/interfaces/IProofOfChange.sol";

contract ProofOfChangeTest is Test {
    ProofOfChange public poc;
    
    address public constant ADMIN = address(1);
    address public constant USER = address(2);
    address public constant SUBDAO_MEMBER = address(3);
    
    uint256 public constant INITIAL_FUNDS = 1 ether;
    uint256 public constant VOTING_PERIOD = 7 days;
    
    bytes32 public constant MOCK_IMAGE_HASH = bytes32(uint256(1));
    
    event ProjectCreated(
        bytes32 indexed projectId,
        address indexed proposer,
        uint256 requestedFunds,
        uint256 duration
    );

    function setUp() public {
        // Deploy ProofOfChange with 7 day voting period
        vm.prank(ADMIN);
        poc = new ProofOfChange(VOTING_PERIOD);
        
        // Setup test accounts
        vm.deal(USER, 10 ether);
        
        // Add DAO and SubDAO members
        vm.startPrank(ADMIN);
        poc.addDAOMember(ADMIN);
        poc.addSubDAOMember(SUBDAO_MEMBER, 1); // Add to region 1
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         PROJECT CREATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testCreateProject() public {
        bytes32 attestationUID = bytes32(uint256(1));
        string memory location = "Test Location";
        uint256 duration = 30 days;
        uint256 regionId = 1;

        vm.prank(USER);
        bytes32 projectId = poc.createProject{value: INITIAL_FUNDS}(
            attestationUID,
            MOCK_IMAGE_HASH,
            location,
            INITIAL_FUNDS,
            regionId,
            duration
        );

        // Verify project details
        ProofOfChange.ProjectDetails memory details = poc.getProjectDetails(projectId);
        
        assertEq(details.proposer, USER);
        assertEq(details.location, location);
        assertEq(details.requestedFunds, INITIAL_FUNDS);
        assertEq(details.regionId, regionId);
        assertEq(details.estimatedDuration, duration);
        assertEq(details.startTime, 0); // Should be 0 until initial phase approval
        assertTrue(details.isActive);
        assertEq(details.currentPhase, 0);
    }

    function testCannotCreateProjectWithoutFunds() public {
        bytes32 attestationUID = bytes32(uint256(1));
        
        vm.prank(USER);
        vm.expectRevert(IProofOfChange.IncorrectFundsSent.selector);
        poc.createProject(
            attestationUID,
            MOCK_IMAGE_HASH,
            "Test Location",
            INITIAL_FUNDS,
            1,
            30 days
        );
    }

    function testCannotCreateProjectWithInvalidDuration() public {
        bytes32 attestationUID = bytes32(uint256(1));
        
        vm.prank(USER);
        vm.expectRevert(IProofOfChange.InvalidDuration.selector);
        poc.createProject{value: INITIAL_FUNDS}(
            attestationUID,
            MOCK_IMAGE_HASH,
            "Test Location",
            INITIAL_FUNDS,
            1,
            0 // Invalid duration
        );
    }

    function testCannotCreateProjectWithInvalidAttestation() public {
        vm.prank(USER);
        vm.expectRevert(IProofOfChange.InvalidAttestation.selector);
        poc.createProject{value: INITIAL_FUNDS}(
            bytes32(0), // Invalid attestation
            MOCK_IMAGE_HASH,
            "Test Location",
            INITIAL_FUNDS,
            1,
            30 days
        );
    }

    /*//////////////////////////////////////////////////////////////
                             VOTING TESTS
    //////////////////////////////////////////////////////////////*/

    function testVotingFlow() public {
        // Create project
        bytes32 projectId = _createTestProject();
        
        // Start voting
        vm.prank(USER);
        poc.startVoting(projectId);
        
        // Cast votes
        vm.prank(ADMIN);
        poc.castVote(projectId, true); // DAO vote
        
        vm.prank(SUBDAO_MEMBER);
        poc.castVote(projectId, true); // SubDAO vote
        
        // Warp time to after voting period
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        
        // Finalize voting
        poc.finalizeVoting(projectId);
        
        // Submit state proof for the initial phase
        vm.prank(USER);
        poc.submitStateProof(
            projectId,
            bytes32(uint256(2)), // New attestation
            MOCK_IMAGE_HASH
        );
        
        // Verify project details after successful vote
        ProofOfChange.ProjectDetails memory details = poc.getProjectDetails(projectId);
        assertTrue(details.startTime > 0); // Should be set after initial phase approval
        assertEq(details.currentPhase, 1); // Should advance to progress phase
    }

    function testCannotVoteTwice() public {
        bytes32 projectId = _createTestProject();
        
        vm.prank(USER);
        poc.startVoting(projectId);
        
        vm.prank(ADMIN);
        poc.castVote(projectId, true);
        
        vm.prank(ADMIN);
        vm.expectRevert(IProofOfChange.AlreadyVoted.selector);
        poc.castVote(projectId, true);
    }

    function testCannotVoteBeforeStart() public {
        bytes32 projectId = _createTestProject();
        
        vm.prank(ADMIN);
        vm.expectRevert(IProofOfChange.VotingNotStarted.selector);
        poc.castVote(projectId, true);
    }

    function testCannotStartVotingTwice() public {
        bytes32 projectId = _createTestProject();
        
        vm.prank(USER);
        poc.startVoting(projectId);
        
        vm.prank(USER);
        vm.expectRevert(IProofOfChange.VotingAlreadyStarted.selector);
        poc.startVoting(projectId);
    }

    function testOnlyProposerCanSubmitStateProof() public {
        bytes32 projectId = _createTestProject();
        
        vm.prank(ADMIN);
        vm.expectRevert(IProofOfChange.NotProposer.selector);
        poc.submitStateProof(
            projectId,
            bytes32(uint256(2)),
            MOCK_IMAGE_HASH
        );
    }

    function testCannotSubmitStateProofForInactiveProject() public {
        bytes32 projectId = _createTestProject();
        
        // Complete all phases
        _completePhaseVoting(projectId);
        _completePhaseVoting(projectId);
        _completePhaseVoting(projectId);
        
        vm.prank(USER);
        vm.expectRevert(IProofOfChange.ProjectNotActive.selector);
        poc.submitStateProof(
            projectId,
            bytes32(uint256(4)),
            MOCK_IMAGE_HASH
        );
    }

    /*//////////////////////////////////////////////////////////////
                         PHASE PROGRESSION TESTS
    //////////////////////////////////////////////////////////////*/

    function testPhaseProgression() public {
        bytes32 projectId = _createTestProject();
        
        // Complete initial phase
        _completePhaseVoting(projectId);
        
        // Submit progress phase proof
        vm.prank(USER);
        poc.submitStateProof(
            projectId,
            bytes32(uint256(2)), // New attestation
            MOCK_IMAGE_HASH
        );
        
        // Complete progress phase
        _completePhaseVoting(projectId);
        
        // Submit completion phase proof
        vm.prank(USER);
        poc.submitStateProof(
            projectId,
            bytes32(uint256(3)), // Final attestation
            MOCK_IMAGE_HASH
        );
        
        // Complete final phase
        _completePhaseVoting(projectId);
        
        // Verify project completion
        ProofOfChange.ProjectDetails memory details = poc.getProjectDetails(projectId);
        assertFalse(details.isActive);
        assertEq(details.currentPhase, 2);
    }

    /*//////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _createTestProject() internal returns (bytes32) {
        vm.prank(USER);
        return poc.createProject{value: INITIAL_FUNDS}(
            bytes32(uint256(1)), // Mock attestation
            MOCK_IMAGE_HASH,
            "Test Location",
            INITIAL_FUNDS,
            1,
            30 days
        );
    }

    function _completePhaseVoting(bytes32 projectId) internal {
        // Start voting
        vm.prank(USER);
        poc.startVoting(projectId);
        
        // Cast votes
        vm.prank(ADMIN);
        poc.castVote(projectId, true);
        
        vm.prank(SUBDAO_MEMBER);
        poc.castVote(projectId, true);
        
        // Warp time to after voting period
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        
        // Finalize voting
        poc.finalizeVoting(projectId);

        // Submit state proof for next phase (except for the final phase)
        ProofOfChange.ProjectDetails memory details = poc.getProjectDetails(projectId);
        if (details.isActive) {
            vm.prank(USER);
            poc.submitStateProof(
                projectId,
                bytes32(uint256(details.currentPhase + 2)), // Increment attestation UID
                MOCK_IMAGE_HASH
            );
        }
    }
}
