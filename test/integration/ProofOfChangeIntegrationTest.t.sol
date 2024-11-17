// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// This integration test is designed to test the complete project lifecycle, including
// project creation, phase completion, and project completion. It also tests the
// functionality of the contract when there is contention over the project's fate.
// Additionally, it checks the contract's robustness against changes in membership
// during the project's lifecycle.

import {Test, console} from "forge-std/Test.sol";
import {ProofOfChange} from "../../src/ProofOfChange.sol";
import {IProofOfChange} from "../../src/interfaces/IProofOfChange.sol";

contract ProofOfChangeIntegrationTest is Test {
    ProofOfChange public poc;
    
    // Test addresses
    address public constant ADMIN = address(1);
    address public constant PROPOSER = address(2);
    address[] public daoMembers;
    address[] public subDaoMembers;
    
    // Test constants
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant PROJECT_DURATION = 90 days;
    uint256 public constant PROJECT_FUNDS = 10 ether;
    uint256 public constant REGION_ID = 1;
    bytes32 public constant MOCK_IMAGE_HASH = bytes32(uint256(1));
    
    function setUp() public {
        // Deploy contract
        vm.prank(ADMIN);
        poc = new ProofOfChange(VOTING_PERIOD);
        
        // Setup test accounts
        daoMembers = [address(3), address(4), address(5)];
        subDaoMembers = [address(6), address(7), address(8)];
        
        // Fund proposer
        vm.deal(PROPOSER, 20 ether);
        
        // Setup DAO members
        vm.startPrank(ADMIN);
        for (uint i = 0; i < daoMembers.length; i++) {
            poc.addDAOMember(daoMembers[i]);
        }
        
        // Setup SubDAO members
        for (uint i = 0; i < subDaoMembers.length; i++) {
            poc.addSubDAOMember(subDaoMembers[i], REGION_ID);
        }
        vm.stopPrank();
    }

    function testCompleteProjectLifecycle() public {
        // ============ Project Creation ============
        bytes32 projectId = _createProject();
        _verifyProjectCreation(projectId);

        // ============ Initial Phase ============
        _completeInitialPhase(projectId);
        _verifyPhaseCompletion(projectId, 0);

        // ============ Progress Phase ============
        _completeProgressPhase(projectId);
        _verifyPhaseCompletion(projectId, 1);

        // ============ Completion Phase ============
        _completeCompletionPhase(projectId);
        _verifyProjectCompletion(projectId);

        // Verify final contract state
        assertEq(poc.getContractBalance(), 0, "Contract should have zero balance");
    }

    function testProjectWithContention() public {
        // Create project
        bytes32 projectId = _createProject();
        uint256 initialProposerBalance = address(PROPOSER).balance;
        uint256 initialContractBalance = poc.getContractBalance();

        // Initial phase with mixed votes
        vm.prank(PROPOSER);
        poc.startVoting(projectId);

        // Some vote yes, some vote no
        vm.prank(daoMembers[0]);
        poc.castVote(projectId, true);
        vm.prank(daoMembers[1]);
        poc.castVote(projectId, false);
        vm.prank(subDaoMembers[0]);
        poc.castVote(projectId, true);
        vm.prank(subDaoMembers[1]);
        poc.castVote(projectId, false);

        // Wait for voting period to end
        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        // Finalize vote
        poc.finalizeVoting(projectId);

        // Verify project state
        ProofOfChange.ProjectDetails memory details = poc.getProjectDetails(projectId);
        assertEq(details.currentPhase, 0, "Project should remain in initial phase");
        assertFalse(details.isActive, "Project should be deactivated after failed vote");
        
        // Verify no funds were released
        assertEq(
            address(PROPOSER).balance, 
            initialProposerBalance, 
            "No funds should be released for failed initial phase"
        );
        assertEq(
            poc.getContractBalance(), 
            initialContractBalance, 
            "All funds should remain in contract"
        );
    }

    function testMembershipChangeDuringProject() public {
        // Create project
        bytes32 projectId = _createProject();

        // Start initial phase voting
        vm.prank(PROPOSER);
        poc.startVoting(projectId);

        // Some members vote
        vm.prank(daoMembers[0]);
        poc.castVote(projectId, true);
        vm.prank(subDaoMembers[0]);
        poc.castVote(projectId, true);

        // Admin removes and adds new members mid-voting
        vm.startPrank(ADMIN);
        poc.removeDAOMember(daoMembers[1]);
        poc.removeSubDAOMember(subDaoMembers[1], REGION_ID);
        
        address newDaoMember = address(9);
        address newSubDaoMember = address(10);
        poc.addDAOMember(newDaoMember);
        poc.addSubDAOMember(newSubDaoMember, REGION_ID);
        vm.stopPrank();

        // New members vote
        vm.prank(newDaoMember);
        poc.castVote(projectId, true);
        vm.prank(newSubDaoMember);
        poc.castVote(projectId, true);

        // Complete voting
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        poc.finalizeVoting(projectId);

        // Verify phase completed successfully
        _verifyPhaseCompletion(projectId, 0);
    }

    function testIncrementalFunding() public {
        // Create project
        bytes32 projectId = _createProject();
        uint256 initialProposerBalance = address(PROPOSER).balance;
        
        // Calculate phase amounts
        uint256 initialPhaseAmount = PROJECT_FUNDS * 25 / 100;    // 25%
        uint256 progressPhaseAmount = PROJECT_FUNDS * 25 / 100;   // 25%
        uint256 completionPhaseAmount = PROJECT_FUNDS * 50 / 100; // 50%

        // Complete initial phase successfully
        _completeInitialPhase(projectId);
        
        // Verify 25% of funds released after initial phase
        assertEq(
            address(PROPOSER).balance, 
            initialProposerBalance + initialPhaseAmount, 
            "25% of funds should be released after initial phase"
        );

        // Complete progress phase successfully
        _completeProgressPhase(projectId);

        // Verify additional 25% released after progress phase
        assertEq(
            address(PROPOSER).balance, 
            initialProposerBalance + initialPhaseAmount + progressPhaseAmount, 
            "50% of funds should be released after progress phase"
        );

        // Complete completion phase successfully
        _completeCompletionPhase(projectId);

        // Verify final 50% released after completion phase
        assertEq(
            address(PROPOSER).balance, 
            initialProposerBalance + initialPhaseAmount + progressPhaseAmount + completionPhaseAmount, 
            "100% of funds should be released after completion"
        );
        
        // Verify project state
        ProofOfChange.ProjectDetails memory details = poc.getProjectDetails(projectId);
        assertFalse(details.isActive, "Project should be deactivated after completion");
        assertEq(details.currentPhase, 2, "Project should be in completion phase");
        assertEq(poc.getContractBalance(), 0, "Contract should have no remaining funds");
    }

    function testPartialSuccessWithCompletionFailure() public {
        // Create project
        bytes32 projectId = _createProject();
        uint256 initialProposerBalance = address(PROPOSER).balance;
        
        // Calculate phase amounts
        uint256 initialPhaseAmount = PROJECT_FUNDS * 25 / 100;    // 25%
        uint256 progressPhaseAmount = PROJECT_FUNDS * 25 / 100;   // 25%

        // Complete initial phase successfully
        _completeInitialPhase(projectId);
        
        // Verify 25% of funds released after initial phase
        assertEq(
            address(PROPOSER).balance, 
            initialProposerBalance + initialPhaseAmount, 
            "25% of funds should be released after initial phase"
        );

        // Complete progress phase successfully
        _completeProgressPhase(projectId);

        // Verify 50% total released after progress phase
        assertEq(
            address(PROPOSER).balance, 
            initialProposerBalance + initialPhaseAmount + progressPhaseAmount, 
            "50% of funds should be released after progress phase"
        );

        // Submit completion phase proof but fail the vote
        vm.prank(PROPOSER);
        poc.submitStateProof(projectId, bytes32(uint256(3)), MOCK_IMAGE_HASH);
        
        vm.prank(PROPOSER);
        poc.startVoting(projectId);

        // Cast failing votes
        for (uint i = 0; i < daoMembers.length; i++) {
            vm.prank(daoMembers[i]);
            poc.castVote(projectId, false);
        }
        for (uint i = 0; i < subDaoMembers.length; i++) {
            vm.prank(subDaoMembers[i]);
            poc.castVote(projectId, false);
        }

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        poc.finalizeVoting(projectId);

        // Verify no additional funds released after failed completion phase
        assertEq(
            address(PROPOSER).balance, 
            initialProposerBalance + initialPhaseAmount + progressPhaseAmount, 
            "Only 50% of funds should be released after failed completion phase"
        );
        
        // Verify remaining 50% stays in contract
        assertEq(
            poc.getContractBalance(), 
            PROJECT_FUNDS * 50 / 100, 
            "50% of funds should remain in contract"
        );
        
        // Verify project state
        ProofOfChange.ProjectDetails memory details = poc.getProjectDetails(projectId);
        assertFalse(details.isActive, "Project should be deactivated after failed vote");
        assertEq(details.currentPhase, 2, "Project should be in completion phase");
    }

    // ============ Helper Functions ============

    function _createProject() internal returns (bytes32) {
        vm.prank(PROPOSER);
        return poc.createProject{value: PROJECT_FUNDS}(
            bytes32(uint256(1)), // Initial attestation
            MOCK_IMAGE_HASH,
            "Test Location",
            PROJECT_FUNDS,
            REGION_ID,
            PROJECT_DURATION
        );
    }

    function _verifyProjectCreation(bytes32 projectId) internal view {
        ProofOfChange.ProjectDetails memory details = poc.getProjectDetails(projectId);
        assertEq(details.proposer, PROPOSER);
        assertEq(details.requestedFunds, PROJECT_FUNDS);
        assertEq(details.regionId, REGION_ID);
        assertEq(details.estimatedDuration, PROJECT_DURATION);
        assertTrue(details.isActive);
        assertEq(details.currentPhase, 0);
    }

    function _completeInitialPhase(bytes32 projectId) internal {
        vm.prank(PROPOSER);
        poc.startVoting(projectId);

        // DAO members vote
        for (uint i = 0; i < daoMembers.length; i++) {
            vm.prank(daoMembers[i]);
            poc.castVote(projectId, true);
        }

        // SubDAO members vote
        for (uint i = 0; i < subDaoMembers.length; i++) {
            vm.prank(subDaoMembers[i]);
            poc.castVote(projectId, true);
        }

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        poc.finalizeVoting(projectId);
    }

    function _completeProgressPhase(bytes32 projectId) internal {
        vm.prank(PROPOSER);
        poc.submitStateProof(
            projectId,
            bytes32(uint256(2)),
            MOCK_IMAGE_HASH
        );

        vm.prank(PROPOSER);
        poc.startVoting(projectId);

        // Cast votes
        for (uint i = 0; i < daoMembers.length; i++) {
            vm.prank(daoMembers[i]);
            poc.castVote(projectId, true);
        }
        for (uint i = 0; i < subDaoMembers.length; i++) {
            vm.prank(subDaoMembers[i]);
            poc.castVote(projectId, true);
        }

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        poc.finalizeVoting(projectId);
    }

    function _completeCompletionPhase(bytes32 projectId) internal {
        vm.prank(PROPOSER);
        poc.submitStateProof(
            projectId,
            bytes32(uint256(3)),
            MOCK_IMAGE_HASH
        );

        vm.prank(PROPOSER);
        poc.startVoting(projectId);

        // Cast votes
        for (uint i = 0; i < daoMembers.length; i++) {
            vm.prank(daoMembers[i]);
            poc.castVote(projectId, true);
        }
        for (uint i = 0; i < subDaoMembers.length; i++) {
            vm.prank(subDaoMembers[i]);
            poc.castVote(projectId, true);
        }

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        poc.finalizeVoting(projectId);
    }

    function _verifyPhaseCompletion(bytes32 projectId, uint8 expectedPhase) internal view {
        ProofOfChange.ProjectDetails memory details = poc.getProjectDetails(projectId);
        
        // Add debug logging
        console.log("Current Phase:", details.currentPhase);
        console.log("Expected Phase:", expectedPhase + 1);
        console.log("Is Active:", details.isActive);
        
        assertEq(details.currentPhase, expectedPhase + 1);
        assertTrue(details.isActive);
        
        (,,,bool completed) = poc.getStateProofDetails(projectId, expectedPhase);
        assertTrue(completed);
    }

    function _verifyProjectCompletion(bytes32 projectId) internal view {
        ProofOfChange.ProjectDetails memory details = poc.getProjectDetails(projectId);
        assertFalse(details.isActive);
        assertEq(details.currentPhase, 2);
        
        // Verify all phases are completed
        for (uint8 i = 0; i < 3; i++) {
            (,,,bool completed) = poc.getStateProofDetails(projectId, i);
            assertTrue(completed);
        }
    }
}


