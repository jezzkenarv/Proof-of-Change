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

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {RetroFund} from "../src/RetroFund.sol";
import "safe-smart-account/contracts/Safe.sol";
import {IRetroFund} from "../src/IRetroFund.sol";

contract RetroFundTest is Test {
    RetroFund public retroFund;
    address public gnosisSafe;

    // Test addresses
    address[] public mainDAOMembers;
    address[] public subDAOMembers;
    address public proposer;

    // Test values for IPFS image hashes, requested amount, and estimated days
    string constant START_IMAGE_HASH = "QmTest123";
    string constant PROGRESS_IMAGE_HASH = "QmProgress456";
    string constant FINAL_IMAGE_HASH = "QmFinal789";
    uint256 constant REQUESTED_AMOUNT = 1 ether;
    uint256 constant ESTIMATED_DAYS = 30;

    function setUp() public {
        // Setup test addresses for Safe wallet, a proposer, 3 Main DAO members, 2 subDAO members
        gnosisSafe = address(new Safe());
        proposer = address(0x1);

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
    // Tests that a proposer can submit a new funding proposal
    // Verifies the proposal details are stored correctly
    function testSubmitProposal() public {
        vm.startPrank(proposer);
        uint256 proposalId = retroFund.submitProposal(START_IMAGE_HASH, REQUESTED_AMOUNT, ESTIMATED_DAYS);
        vm.stopPrank();

        RetroFund.Proposal memory proposal = retroFund.proposals(proposalId);
        assertEq(proposal.proposer, proposer);
        assertEq(proposal.requestedAmount, REQUESTED_AMOUNT);
        assertEq(proposal.initialVoting.startImageHash, START_IMAGE_HASH);
    }

    // Test main DAO voting
    // Verifies that votes are counted correctly and approval flags are set
    function testMainDAOVoting() public {
        // Submit proposal
        vm.prank(proposer);
        uint256 proposalId = retroFund.submitProposal(START_IMAGE_HASH, REQUESTED_AMOUNT, ESTIMATED_DAYS);

        // Vote from main DAO members
        for (uint256 i = 0; i < mainDAOMembers.length; i++) {
            vm.prank(mainDAOMembers[i]);
            retroFund.voteFromMainDAO(proposalId, true);

            // Debug: Check state after each vote
            RetroFund.Proposal memory proposalState = retroFund.proposals(proposalId);
            console.log("Vote", i + 1);
            console.log("Votes For:", proposalState.initialVoting.mainDAOVotesInFavor);
            console.log("Votes Against:", proposalState.initialVoting.mainDAOVotesAgainst);
            console.log("Approved:", proposalState.initialVoting.mainDAOApproved);
        }

        // Final check
        RetroFund.Proposal memory finalState = retroFund.proposals(proposalId);
        assertEq(finalState.initialVoting.mainDAOVotesInFavor, 3);
        assertTrue(finalState.initialVoting.mainDAOApproved);
    }

    // Test sub DAO voting
    function testSubDAOVoting() public {
        // Submit proposal
        vm.prank(proposer);
        uint256 proposalId = retroFund.submitProposal(START_IMAGE_HASH, REQUESTED_AMOUNT, ESTIMATED_DAYS);

        // Vote from sub DAO members
        for (uint256 i = 0; i < subDAOMembers.length; i++) {
            vm.prank(subDAOMembers[i]);
            retroFund.voteFromSubDAO(proposalId, true);

            // Debug: Check state after each vote
            RetroFund.Proposal memory proposalState = retroFund.proposals(proposalId);
            console.log("Vote", i + 1);
            console.log("Votes For:", proposalState.initialVoting.subDAOVotesInFavor);
            console.log("Votes Against:", proposalState.initialVoting.subDAOVotesAgainst);
            console.log("Approved:", proposalState.initialVoting.subDAOApproved);
            
            // Add these debug lines to help identify the issue
            console.log("Total subDAO members:", subDAOMembers.length);
            console.log("Current votes:", proposalState.initialVoting.subDAOVotesInFavor);
        }

        // Final check
        RetroFund.Proposal memory finalState = retroFund.proposals(proposalId);
        
        // Add this line to see the final state before assertions
        console.log("Final votes in favor:", finalState.initialVoting.subDAOVotesInFavor);
        console.log("Final approval state:", finalState.initialVoting.subDAOApproved);
        
        assertEq(finalState.initialVoting.subDAOVotesInFavor, 3);
        assertTrue(finalState.initialVoting.subDAOApproved);
    }

    // Test proposal finalization
    function testFinalizeVoting() public {
        // Submit proposal
        vm.prank(proposer);
        uint256 proposalId = retroFund.submitProposal(START_IMAGE_HASH, REQUESTED_AMOUNT, ESTIMATED_DAYS);

        // Vote from both DAOs
        for (uint256 i = 0; i < mainDAOMembers.length; i++) {
            vm.prank(mainDAOMembers[i]);
            retroFund.voteFromMainDAO(proposalId, true);
        }
        for (uint256 i = 0; i < subDAOMembers.length; i++) {
            vm.prank(subDAOMembers[i]);
            retroFund.voteFromSubDAO(proposalId, true);
        }

        // Wait for cooldown period
        vm.warp(block.timestamp + retroFund.COOLDOWN_PERIOD());

        // Finalize voting
        retroFund.finalizeVoting(proposalId);

        RetroFund.Proposal memory proposal = retroFund.proposals(proposalId);
        assertTrue(proposal.initialVoting.stageApproved);
    }

    // Test progress voting
    function testProgressVoting() public {
        // Setup approved proposal
        vm.prank(proposer);
        uint256 proposalId = retroFund.submitProposal(START_IMAGE_HASH, REQUESTED_AMOUNT, ESTIMATED_DAYS);

        // Initial voting approval
        for (uint256 i = 0; i < mainDAOMembers.length; i++) {
            vm.prank(mainDAOMembers[i]);
            retroFund.voteFromMainDAO(proposalId, true);
        }
        for (uint256 i = 0; i < subDAOMembers.length; i++) {
            vm.prank(subDAOMembers[i]);
            retroFund.voteFromSubDAO(proposalId, true);
        }

        vm.warp(block.timestamp + retroFund.COOLDOWN_PERIOD());
        retroFund.finalizeVoting(proposalId);

        // Warp to progress voting window
        RetroFund.Proposal memory proposal = retroFund.proposals(proposalId);
        vm.warp(proposal.midpointTime);

        // Test progress voting
        for (uint256 i = 0; i < mainDAOMembers.length; i++) {
            vm.prank(mainDAOMembers[i]);
            retroFund.voteOnProgressFromMainDAO(proposalId, true);

            // Debug: Check mainDAO state after each vote
            RetroFund.Proposal memory proposalState = retroFund.proposals(proposalId);
            console.log("MainDAO Vote", i + 1);
            console.log("MainDAO Votes For:", proposalState.progressVoting.mainDAOVotesInFavor);
            console.log("MainDAO Votes Against:", proposalState.progressVoting.mainDAOVotesAgainst);
            console.log("MainDAO Approved:", proposalState.progressVoting.mainDAOApproved);
        }

        for (uint256 i = 0; i < subDAOMembers.length; i++) {
            vm.prank(subDAOMembers[i]);
            retroFund.voteOnProgressFromSubDAO(proposalId, true);

            // Debug: Check subDAO state after each vote
            RetroFund.Proposal memory proposalState = retroFund.proposals(proposalId);
            console.log("SubDAO Vote", i + 1);
            console.log("SubDAO Votes For:", proposalState.progressVoting.subDAOVotesInFavor);
            console.log("SubDAO Votes Against:", proposalState.progressVoting.subDAOVotesAgainst);
            console.log("SubDAO Approved:", proposalState.progressVoting.subDAOApproved);
        }

        // Add final state logging
        RetroFund.Proposal memory finalState = retroFund.proposals(proposalId);
        console.log("\nFinal Voting State:");
        console.log("Final MainDAO votes in favor:", finalState.progressVoting.mainDAOVotesInFavor);
        console.log("Final SubDAO votes in favor:", finalState.progressVoting.subDAOVotesInFavor);
        console.log("MainDAO approved:", finalState.progressVoting.mainDAOApproved);
        console.log("SubDAO approved:", finalState.progressVoting.subDAOApproved);

        proposal = retroFund.proposals(proposalId);
        assertTrue(proposal.progressVoting.mainDAOApproved);
        assertTrue(proposal.progressVoting.subDAOApproved);
    }

    // Test completion process
    function testCompletionProcess() public {
        // Setup approved proposal with progress approved
        vm.prank(proposer);
        uint256 proposalId = retroFund.submitProposal(START_IMAGE_HASH, REQUESTED_AMOUNT, ESTIMATED_DAYS);

        // Initial voting setup
        for (uint256 i = 0; i < mainDAOMembers.length; i++) {
            vm.prank(mainDAOMembers[i]);
            retroFund.voteFromMainDAO(proposalId, true);
        }
        for (uint256 i = 0; i < subDAOMembers.length; i++) {
            vm.prank(subDAOMembers[i]);
            retroFund.voteFromSubDAO(proposalId, true);
        }

        // Wait for cooldown and finalize initial voting
        vm.warp(block.timestamp + retroFund.COOLDOWN_PERIOD());
        retroFund.finalizeVoting(proposalId);

        // Progress voting setup
        vm.warp(retroFund.proposals(proposalId).midpointTime);
        console.log("\n=== Progress Voting Phase ===");

        // Vote from main DAO members (only once per member)
        for (uint256 i = 0; i < mainDAOMembers.length; i++) {
            vm.prank(mainDAOMembers[i]);
            retroFund.voteOnProgressFromMainDAO(proposalId, true);

            // Debug: Check mainDAO state after each vote
            RetroFund.Proposal memory proposalState = retroFund.proposals(proposalId);
            console.log("MainDAO Vote", i + 1);
            console.log("MainDAO Votes For:", proposalState.progressVoting.mainDAOVotesInFavor);
            console.log("MainDAO Votes Against:", proposalState.progressVoting.mainDAOVotesAgainst);
            console.log("MainDAO Approved:", proposalState.progressVoting.mainDAOApproved);
        }

        for (uint256 i = 0; i < subDAOMembers.length; i++) {
            vm.prank(subDAOMembers[i]);
            retroFund.voteOnProgressFromSubDAO(proposalId, true);

            // Debug: Check subDAO state after each vote
            RetroFund.Proposal memory proposalState = retroFund.proposals(proposalId);
            console.log("SubDAO Vote", i + 1);
            console.log("SubDAO Votes For:", proposalState.progressVoting.subDAOVotesInFavor);
            console.log("SubDAO Votes Against:", proposalState.progressVoting.subDAOVotesAgainst);
            console.log("SubDAO Approved:", proposalState.progressVoting.subDAOApproved);
        }

        // Finalize progress voting
        vm.warp(block.timestamp + retroFund.COOLDOWN_PERIOD());
        retroFund.finalizeVoting(proposalId);
        
        // // Verify progress voting was finalized
        // RetroFund.Proposal memory progressState = retroFund.proposals(proposalId);

        // Warp to completion time
        RetroFund.Proposal memory completionState = retroFund.proposals(proposalId);
        vm.warp(completionState.estimatedCompletionTime);

        // Continue with completion phase
        vm.prank(proposer);
        retroFund.declareProjectCompletion(proposalId, FINAL_IMAGE_HASH);

        // Vote on completion
        for (uint256 i = 0; i < mainDAOMembers.length; i++) {
            vm.prank(mainDAOMembers[i]);
            retroFund.voteOnCompletionFromMainDAO(proposalId, true);
        }
        for (uint256 i = 0; i < subDAOMembers.length; i++) {
            vm.prank(subDAOMembers[i]);
            retroFund.voteOnCompletionFromSubDAO(proposalId, true);
        }

        RetroFund.Proposal memory proposal = retroFund.proposals(proposalId);
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
        // The test will fail if the expected revert message doesn't match exactly with the actual revert message
        vm.expectRevert("Not a member of the main DAO");
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
        vm.expectRevert("revert: Proposal must be approved before completion");
        retroFund.declareProjectCompletion(proposalId, FINAL_IMAGE_HASH);
    }
}
