// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// So far tests cover:
// A full proposal lifecycle
// Rejections at each stage
// Release of funds
// Edge cases around voting windows
// Invalid operation attempts
// Different voting combinations
// Fund release failures
// Invalid proposal parameters

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {RetroFund} from "../../src/RetroFund.sol";
import "safe-smart-account/contracts/Safe.sol";
import {IRetroFund} from "../../src/Interfaces/IRetroFund.sol";

contract RetroFundIntegrationTest is Test {
    // RetroFund public retroFund;
    // address public gnosisSafe;
    
    // // Test accounts
    // address[] public mainDAOMembers;
    // address[] public subDAOMembers;
    // address public proposer;
    
    // // Test proposal data
    // uint256 public constant REQUESTED_AMOUNT = 1 ether;
    // string public constant START_IMAGE_HASH = "ipfs://start-hash";
    // string public constant PROGRESS_IMAGE_HASH = "ipfs://progress-hash";
    // string public constant FINAL_IMAGE_HASH = "ipfs://final-hash";
    // uint256 public constant ESTIMATED_DAYS = 10;
    
    // function setUp() public {
    //     // Setup test accounts
    //     proposer = makeAddr("proposer");
        
    //     // Setup 3 members for each DAO
    //     for (uint i = 0; i < 3; i++) {
    //         mainDAOMembers.push(makeAddr(string.concat("mainDAO", vm.toString(i))));
    //         subDAOMembers.push(makeAddr(string.concat("subDAO", vm.toString(i))));
    //     }
        
    //     // Deploy mock Safe
    //     gnosisSafe = address(new Safe());
        
    //     // Fund the Safe
    //     vm.deal(gnosisSafe, 10 ether);
        
    //     // Deploy RetroFund
    //     retroFund = new RetroFund(gnosisSafe, mainDAOMembers, subDAOMembers);
    // }

    // function test_FullProposalLifecycle() public {
    //     // Submit proposal
    //     vm.startPrank(proposer);
    //     uint256 proposalId = retroFund.submitProposal(
    //         START_IMAGE_HASH,
    //         REQUESTED_AMOUNT,
    //         ESTIMATED_DAYS,
    //         "Test Proposal",
    //         "Test Description",
    //         new string[](0), // tags
    //         "Test Documentation",
    //         new string[](0)  // external links
    //     );
    //     vm.stopPrank();

    //     // Initial voting phase
    //     _completeInitialVoting(proposalId, true);
        
    //     // Progress phase
    //     vm.warp(block.timestamp + (ESTIMATED_DAYS * 1 days) / 2); // Warp to midpoint
        
    //     vm.prank(proposer);
    //     retroFund.submitProgressImage(proposalId, PROGRESS_IMAGE_HASH);
        
    //     _completeProgressVoting(proposalId, true);

    //     // Completion phase
    //     vm.warp(block.timestamp + (ESTIMATED_DAYS * 1 days) / 2); // Warp to completion
        
    //     vm.prank(proposer);
    //     retroFund.declareProjectCompletion(proposalId, FINAL_IMAGE_HASH);
        
    //     _completeCompletionVoting(proposalId, true);

    //     // Release funds
    //     uint256 balanceBefore = proposer.balance;
    //     retroFund.releaseFunds(proposalId);
    //     assertEq(proposer.balance - balanceBefore, REQUESTED_AMOUNT);
    // }

    // function test_RejectAtInitialVoting() public {
    //     uint256 proposalId = _submitTestProposal();
    //     _completeInitialVoting(proposalId, false);
        
    //     IRetroFund.Proposal memory proposal = retroFund.proposals(proposalId);
    //     assertTrue(proposal.isRejected);
    // }

    // function test_RejectAtProgressVoting() public {
    //     uint256 proposalId = _submitTestProposal();
    //     _completeInitialVoting(proposalId, true);
        
    //     vm.warp(block.timestamp + (ESTIMATED_DAYS * 1 days) / 2);
        
    //     vm.prank(proposer);
    //     retroFund.submitProgressImage(proposalId, PROGRESS_IMAGE_HASH);
        
    //     _completeProgressVoting(proposalId, false);
        
    //     IRetroFund.Proposal memory proposal = retroFund.proposals(proposalId);
    //     assertTrue(proposal.isRejected);
    // }

    // // Edge cases around voting windows
    // function test_VotingWindowEdgeCases() public {
    //     uint256 proposalId = _submitTestProposal();
        
    //     // Try voting before cooldown
    //     vm.prank(mainDAOMembers[0]);
    //     retroFund.voteFromMainDAO(proposalId, true);
        
    //     // Try voting after cooldown
    //     vm.warp(block.timestamp + retroFund.COOLDOWN_PERIOD() + 1);
    //     vm.prank(mainDAOMembers[1]);
    //     vm.expectRevert("Voting period ended");
    //     retroFund.voteFromMainDAO(proposalId, true);
        
    //     // Test progress voting window
    //     _completeInitialVoting(proposalId, true);
        
    //     // Try voting too early for progress
    //     vm.prank(mainDAOMembers[0]);
    //     vm.expectRevert("Not in progress voting window");
    //     retroFund.voteOnProgressFromMainDAO(proposalId, true);
        
    //     // Move to just before progress window
    //     uint256 midpoint = (ESTIMATED_DAYS * 1 days) / 2;
    //     vm.warp(block.timestamp + midpoint - 4 days);
    //     vm.prank(mainDAOMembers[0]);
    //     vm.expectRevert("Not in progress voting window");
    //     retroFund.voteOnProgressFromMainDAO(proposalId, true);
        
    //     // Move to valid progress window
    //     vm.warp(block.timestamp + 1 days);
    //     vm.prank(proposer);
    //     retroFund.submitProgressImage(proposalId, PROGRESS_IMAGE_HASH);
        
    //     vm.prank(mainDAOMembers[0]);
    //     retroFund.voteOnProgressFromMainDAO(proposalId, true);
    // }

    // // Invalid operation attempts
    // function test_InvalidOperations() public {
    //     uint256 proposalId = _submitTestProposal();
        
    //     // Try submitting progress before initial approval
    //     vm.prank(proposer);
    //     vm.expectRevert("Initial voting must be approved first");
    //     retroFund.submitProgressImage(proposalId, PROGRESS_IMAGE_HASH);
        
    //     // Try voting from non-member
    //     address nonMember = makeAddr("nonMember");
    //     vm.prank(nonMember);
    //     vm.expectRevert("RetroFundNotMainDAOmember");
    //     retroFund.voteFromMainDAO(proposalId, true);
        
    //     // Try completing project before progress approval
    //     vm.prank(proposer);
    //     vm.expectRevert("Progress voting must be approved first");
    //     retroFund.declareProjectCompletion(proposalId, FINAL_IMAGE_HASH);
        
    //     // Try releasing funds before completion
    //     vm.expectRevert("Project must be completed");
    //     retroFund.releaseFunds(proposalId);
        
    //     // Try double voting
    //     vm.prank(mainDAOMembers[0]);
    //     retroFund.voteFromMainDAO(proposalId, true);
        
    //     vm.prank(mainDAOMembers[0]);
    //     vm.expectRevert("Already voted");
    //     retroFund.voteFromMainDAO(proposalId, true);
    // }

    // // Different voting combinations
    // function test_VotingCombinations() public {
    //     uint256 proposalId = _submitTestProposal();
        
    //     // Scenario: MainDAO approves, SubDAO rejects
    //     for (uint i = 0; i < mainDAOMembers.length; i++) {
    //         vm.prank(mainDAOMembers[i]);
    //         retroFund.voteFromMainDAO(proposalId, true);
    //     }
        
    //     for (uint i = 0; i < subDAOMembers.length; i++) {
    //         vm.prank(subDAOMembers[i]);
    //         retroFund.voteFromSubDAO(proposalId, false);
    //     }
        
    //     vm.warp(block.timestamp + retroFund.COOLDOWN_PERIOD());
    //     retroFund.finalizeVoting(proposalId);
        
    //     IRetroFund.Proposal memory proposal = retroFund.proposals(proposalId);
    //     assertTrue(proposal.isRejected);
        
    //     // Test split votes within MainDAO
    //     proposalId = _submitTestProposal();
        
    //     // 2 approve, 1 reject in MainDAO
    //     vm.prank(mainDAOMembers[0]);
    //     retroFund.voteFromMainDAO(proposalId, true);
    //     vm.prank(mainDAOMembers[1]);
    //     retroFund.voteFromMainDAO(proposalId, true);
    //     vm.prank(mainDAOMembers[2]);
    //     retroFund.voteFromMainDAO(proposalId, false);
        
    //     // All approve in SubDAO
    //     for (uint i = 0; i < subDAOMembers.length; i++) {
    //         vm.prank(subDAOMembers[i]);
    //         retroFund.voteFromSubDAO(proposalId, true);
    //     }
        
    //     vm.warp(block.timestamp + retroFund.COOLDOWN_PERIOD());
    //     retroFund.finalizeVoting(proposalId);
        
    //     proposal = retroFund.proposals(proposalId);
    //     assertFalse(proposal.isRejected);
    // }

    // // Fund release failures
    // function test_FundReleaseFailures() public {
    //     // Setup a new Safe with no funds
    //     address emptySafe = address(new Safe());
    //     RetroFund newRetroFund = new RetroFund(
    //         emptySafe,
    //         mainDAOMembers,
    //         subDAOMembers
    //     );
        
    //     // Complete full proposal lifecycle
    //     vm.startPrank(proposer);
    //     uint256 proposalId = newRetroFund.submitProposal(
    //         START_IMAGE_HASH,
    //         REQUESTED_AMOUNT,
    //         ESTIMATED_DAYS,
    //         "Test Proposal",
    //         "Test Description",
    //         new string[](0),
    //         "Test Documentation",
    //         new string[](0)
    //     );
    //     vm.stopPrank();
        
    //     // Complete all voting stages
    //     _completeInitialVoting(proposalId, true);
        
    //     vm.warp(block.timestamp + (ESTIMATED_DAYS * 1 days) / 2);
    //     vm.prank(proposer);
    //     newRetroFund.submitProgressImage(proposalId, PROGRESS_IMAGE_HASH);
    //     _completeProgressVoting(proposalId, true);
        
    //     vm.warp(block.timestamp + (ESTIMATED_DAYS * 1 days) / 2);
    //     vm.prank(proposer);
    //     newRetroFund.declareProjectCompletion(proposalId, FINAL_IMAGE_HASH);
    //     _completeCompletionVoting(proposalId, true);
        
    //     // Try to release funds from empty safe
    //     vm.expectRevert("Fund release transaction failed");
    //     newRetroFund.releaseFunds(proposalId);
        
    //     // Test double release prevention
    //     proposalId = _submitTestProposal();
    //     _completeInitialVoting(proposalId, true);
        
    //     vm.warp(block.timestamp + (ESTIMATED_DAYS * 1 days) / 2);
    //     vm.prank(proposer);
    //     retroFund.submitProgressImage(proposalId, PROGRESS_IMAGE_HASH);
    //     _completeProgressVoting(proposalId, true);
        
    //     vm.warp(block.timestamp + (ESTIMATED_DAYS * 1 days) / 2);
    //     vm.prank(proposer);
    //     retroFund.declareProjectCompletion(proposalId, FINAL_IMAGE_HASH);
    //     _completeCompletionVoting(proposalId, true);
        
    //     retroFund.releaseFunds(proposalId);
        
    //     vm.expectRevert("Funds already released");
    //     retroFund.releaseFunds(proposalId);
    // }

    // // Test invalid proposal parameters
    // function test_InvalidProposalParameters() public {
    //     vm.startPrank(proposer);
        
    //     // Test zero amount
    //     vm.expectRevert("RetroFundInvalidAmount");
    //     retroFund.submitProposal(
    //         START_IMAGE_HASH,
    //         0,
    //         ESTIMATED_DAYS,
    //         "Test Proposal",
    //         "Test Description",
    //         new string[](0),
    //         "Test Documentation",
    //         new string[](0)
    //     );
        
    //     // Test empty image hash
    //     vm.expectRevert("RetroFundEmptyImageHash");
    //     retroFund.submitProposal(
    //         "",
    //         REQUESTED_AMOUNT,
    //         ESTIMATED_DAYS,
    //         "Test Proposal",
    //         "Test Description",
    //         new string[](0),
    //         "Test Documentation",
    //         new string[](0)
    //     );
        
    //     // Test zero duration
    //     vm.expectRevert("RetroFundInvalidDuration");
    //     retroFund.submitProposal(
    //         START_IMAGE_HASH,
    //         REQUESTED_AMOUNT,
    //         0,
    //         "Test Proposal",
    //         "Test Description",
    //         new string[](0),
    //         "Test Documentation",
    //         new string[](0)
    //     );
        
    //     // Test empty title
    //     vm.expectRevert("RetroFundEmptyTitle");
    //     retroFund.submitProposal(
    //         START_IMAGE_HASH,
    //         REQUESTED_AMOUNT,
    //         ESTIMATED_DAYS,
    //         "",
    //         "Test Description",
    //         new string[](0),
    //         "Test Documentation",
    //         new string[](0)
    //     );
        
    //     // Test empty description
    //     vm.expectRevert("RetroFundEmptyDescription");
    //     retroFund.submitProposal(
    //         START_IMAGE_HASH,
    //         REQUESTED_AMOUNT,
    //         ESTIMATED_DAYS,
    //         "Test Proposal",
    //         "",
    //         new string[](0),
    //         "Test Documentation",
    //         new string[](0)
    //     );
        
    //     vm.stopPrank();
    // }

    // // Helper functions
    // function _submitTestProposal() internal returns (uint256) {
    //     vm.prank(proposer);
    //     return retroFund.submitProposal(
    //         START_IMAGE_HASH,
    //         REQUESTED_AMOUNT,
    //         ESTIMATED_DAYS,
    //         "Test Proposal",
    //         "Test Description",
    //         new string[](0),
    //         "Test Documentation",
    //         new string[](0)
    //     );
    // }

    // function _completeInitialVoting(uint256 proposalId, bool approve) internal {
    //     // Main DAO voting
    //     for (uint i = 0; i < mainDAOMembers.length; i++) {
    //         vm.prank(mainDAOMembers[i]);
    //         retroFund.voteFromMainDAO(proposalId, approve);
    //     }
        
    //     // Sub DAO voting
    //     for (uint i = 0; i < subDAOMembers.length; i++) {
    //         vm.prank(subDAOMembers[i]);
    //         retroFund.voteFromSubDAO(proposalId, approve);
    //     }
        
    //     // Warp past cooldown and finalize
    //     vm.warp(block.timestamp + retroFund.COOLDOWN_PERIOD());
    //     retroFund.finalizeVoting(proposalId);
    // }

    // function _completeProgressVoting(uint256 proposalId, bool approve) internal {
    //     // Main DAO voting
    //     for (uint i = 0; i < mainDAOMembers.length; i++) {
    //         vm.prank(mainDAOMembers[i]);
    //         retroFund.voteOnProgressFromMainDAO(proposalId, approve);
    //     }
        
    //     // Sub DAO voting
    //     for (uint i = 0; i < subDAOMembers.length; i++) {
    //         vm.prank(subDAOMembers[i]);
    //         retroFund.voteOnProgressFromSubDAO(proposalId, approve);
    //     }
        
    //     // Warp past cooldown and finalize
    //     vm.warp(block.timestamp + retroFund.COOLDOWN_PERIOD());
    //     retroFund.finalizeVoting(proposalId);
    // }

    // function _completeCompletionVoting(uint256 proposalId, bool approve) internal {
    //     // Main DAO voting
    //     for (uint i = 0; i < mainDAOMembers.length; i++) {
    //         vm.prank(mainDAOMembers[i]);
    //         retroFund.voteOnCompletionFromMainDAO(proposalId, approve);
    //     }
        
    //     // Sub DAO voting
    //     for (uint i = 0; i < subDAOMembers.length; i++) {
    //         vm.prank(subDAOMembers[i]);
    //         retroFund.voteOnCompletionFromSubDAO(proposalId, approve);
    //     }
        
    //     // Warp past cooldown and finalize
    //     vm.warp(block.timestamp + retroFund.COOLDOWN_PERIOD());
    //     retroFund.finalizeVoting(proposalId);
    // }
}


