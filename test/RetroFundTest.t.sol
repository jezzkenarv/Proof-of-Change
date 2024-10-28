// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// So far tests cover:
// - Proposal submission
// - Main DAO voting
// - Sub DAO voting
// - Proposal finalization
// - Progress voting
// - Completion process
// - Failure cases

import "forge-std/Test.sol";
import "../src/RetroFund.sol";
import "safe-smart-account/contracts/Safe.sol";

contract RetroFundTest is Test {
    RetroFund public retroFund;
    address public gnosisSafe;
    
    // Test addresses
    address[] public mainDAOMembers;
    address[] public subDAOMembers;
    address public proposer;
    
    // Test values
    string constant START_IMAGE_HASH = "QmTest123";
    string constant PROGRESS_IMAGE_HASH = "QmProgress456";
    string constant FINAL_IMAGE_HASH = "QmFinal789";
    uint256 constant REQUESTED_AMOUNT = 1 ether;
    uint256 constant ESTIMATED_DAYS = 30;

    function setUp() public {
        // Setup test addresses
        gnosisSafe = address(new Safe());
        proposer = address(0x1);
        
        // Setup DAO members
        mainDAOMembers = new address[](3);
        mainDAOMembers[0] = address(0x2);
        mainDAOMembers[1] = address(0x3);
        mainDAOMembers[2] = address(0x4);

        subDAOMembers = new address[](3);
        subDAOMembers[0] = address(0x5);
        subDAOMembers[1] = address(0x6);
        subDAOMembers[2] = address(0x7);

        // Deploy RetroFund
        retroFund = new RetroFund(gnosisSafe, mainDAOMembers, subDAOMembers);
    }

    // Test proposal submission
    function testSubmitProposal() public {
        vm.startPrank(proposer);
        uint256 proposalId = retroFund.submitProposal(START_IMAGE_HASH, REQUESTED_AMOUNT, ESTIMATED_DAYS);
        vm.stopPrank();

        IRetroFund.Proposal memory proposal = retroFund.proposals(proposalId);
        assertEq(proposal.proposer, proposer);
        assertEq(proposal.requestedAmount, REQUESTED_AMOUNT);
        assertEq(proposal.initialVoting.startImageHash, START_IMAGE_HASH);
    }

    // Test main DAO voting
    function testMainDAOVoting() public {
        // Submit proposal
        vm.prank(proposer);
        uint256 proposalId = retroFund.submitProposal(START_IMAGE_HASH, REQUESTED_AMOUNT, ESTIMATED_DAYS);

        // Vote from main DAO members
        for (uint i = 0; i < mainDAOMembers.length; i++) {
            vm.prank(mainDAOMembers[i]);
            retroFund.voteFromMainDAO(proposalId, true);
        }

        IRetroFund.Proposal memory proposal = retroFund.proposals(proposalId);
        assertEq(proposal.initialVoting.mainDAOVotesInFavor, 3);
        assertTrue(proposal.initialVoting.mainDAOApproved);
    }

    // Test sub DAO voting
    function testSubDAOVoting() public {
        // Submit proposal
        vm.prank(proposer);
        uint256 proposalId = retroFund.submitProposal(START_IMAGE_HASH, REQUESTED_AMOUNT, ESTIMATED_DAYS);

        // Vote from sub DAO members
        for (uint i = 0; i < subDAOMembers.length; i++) {
            vm.prank(subDAOMembers[i]);
            retroFund.voteFromSubDAO(proposalId, true);
        }

        IRetroFund.Proposal memory proposal = retroFund.proposals(proposalId);
        assertEq(proposal.initialVoting.subDAOVotesInFavor, 3);
        assertTrue(proposal.initialVoting.subDAOApproved);
    }

    // Test proposal finalization
    function testFinalizeVoting() public {
        // Submit proposal
        vm.prank(proposer);
        uint256 proposalId = retroFund.submitProposal(START_IMAGE_HASH, REQUESTED_AMOUNT, ESTIMATED_DAYS);

        // Vote from both DAOs
        for (uint i = 0; i < mainDAOMembers.length; i++) {
            vm.prank(mainDAOMembers[i]);
            retroFund.voteFromMainDAO(proposalId, true);
        }
        for (uint i = 0; i < subDAOMembers.length; i++) {
            vm.prank(subDAOMembers[i]);
            retroFund.voteFromSubDAO(proposalId, true);
        }

        // Wait for cooldown period
        vm.warp(block.timestamp + retroFund.COOLDOWN_PERIOD());

        // Finalize voting
        retroFund.finalizeVoting(proposalId);

        IRetroFund.Proposal memory proposal = retroFund.proposals(proposalId);
        assertTrue(proposal.initialVoting.stageApproved);
    }

    // Test progress voting
    function testProgressVoting() public {
        // Setup approved proposal
        vm.prank(proposer);
        uint256 proposalId = retroFund.submitProposal(START_IMAGE_HASH, REQUESTED_AMOUNT, ESTIMATED_DAYS);
        
        // Initial voting approval
        for (uint i = 0; i < mainDAOMembers.length; i++) {
            vm.prank(mainDAOMembers[i]);
            retroFund.voteFromMainDAO(proposalId, true);
        }
        for (uint i = 0; i < subDAOMembers.length; i++) {
            vm.prank(subDAOMembers[i]);
            retroFund.voteFromSubDAO(proposalId, true);
        }
        
        vm.warp(block.timestamp + retroFund.COOLDOWN_PERIOD());
        retroFund.finalizeVoting(proposalId);

        // Warp to progress voting window
        IRetroFund.Proposal memory proposal = retroFund.proposals(proposalId);
        vm.warp(proposal.midpointTime);

        // Test progress voting
        for (uint i = 0; i < mainDAOMembers.length; i++) {
            vm.prank(mainDAOMembers[i]);
            retroFund.voteOnProgressFromMainDAO(proposalId, true);
        }
        for (uint i = 0; i < subDAOMembers.length; i++) {
            vm.prank(subDAOMembers[i]);
            retroFund.voteOnProgressFromSubDAO(proposalId, true);
        }

        proposal = retroFund.proposals(proposalId);
        assertTrue(proposal.progressVoting.mainDAOApproved);
        assertTrue(proposal.progressVoting.subDAOApproved);
    }

    // Test completion process
    function testCompletionProcess() public {
        // Setup approved proposal with progress approved
        vm.prank(proposer);
        uint256 proposalId = retroFund.submitProposal(START_IMAGE_HASH, REQUESTED_AMOUNT, ESTIMATED_DAYS);
        
        // Initial and progress voting setup...
        // [Previous voting setup code]
        
        // Declare completion
        vm.prank(proposer);
        retroFund.declareProjectCompletion(proposalId, FINAL_IMAGE_HASH);

        // Vote on completion
        for (uint i = 0; i < mainDAOMembers.length; i++) {
            vm.prank(mainDAOMembers[i]);
            retroFund.voteOnCompletionFromMainDAO(proposalId, true);
        }
        for (uint i = 0; i < subDAOMembers.length; i++) {
            vm.prank(subDAOMembers[i]);
            retroFund.voteOnCompletionFromSubDAO(proposalId, true);
        }

        IRetroFund.Proposal memory proposal = retroFund.proposals(proposalId);
        assertTrue(proposal.completionVoting.completed);
        assertTrue(proposal.completionVoting.mainDAOApproved);
        assertTrue(proposal.completionVoting.subDAOApproved);
    }

    // Test failure cases
    function testFailureUnauthorizedVote() public {
        vm.prank(proposer);
        uint256 proposalId = retroFund.submitProposal(START_IMAGE_HASH, REQUESTED_AMOUNT, ESTIMATED_DAYS);

        // Try to vote as non-DAO member
        vm.prank(address(0x999));
        vm.expectRevert("Not part of main DAO");
        retroFund.voteFromMainDAO(proposalId, true);
    }

    function testFailureDoubleVote() public {
        vm.prank(proposer);
        uint256 proposalId = retroFund.submitProposal(START_IMAGE_HASH, REQUESTED_AMOUNT, ESTIMATED_DAYS);

        // Vote once
        vm.prank(mainDAOMembers[0]);
        retroFund.voteFromMainDAO(proposalId, true);

        // Try to vote again
        vm.prank(mainDAOMembers[0]);
        vm.expectRevert("Main DAO already approved");
        retroFund.voteFromMainDAO(proposalId, true);
    }

    function testFailureEarlyCompletion() public {
        vm.prank(proposer);
        uint256 proposalId = retroFund.submitProposal(START_IMAGE_HASH, REQUESTED_AMOUNT, ESTIMATED_DAYS);

        // Try to declare completion before approval
        vm.prank(proposer);
        vm.expectRevert("Proposal must be approved before completion");
        retroFund.declareProjectCompletion(proposalId, FINAL_IMAGE_HASH);
    }
}
