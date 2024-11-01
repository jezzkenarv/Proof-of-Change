// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// So far tests cover:
// - Proposal submission
// - Main DAO voting
// - Sub DAO voting
// - Failure cases

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {RetroFund} from "../../src/RetroFund.sol";
import "safe-smart-account/contracts/Safe.sol";
import {IRetroFund} from "../../src/IRetroFund.sol";

contract RetroFundUnitTest is Test {
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

    // Test values for metadata
    string constant TEST_TITLE = "Test Project";
    string constant TEST_DESCRIPTION = "Test project description";
    string constant TEST_DOCUMENTATION = "ipfs://test-docs";

    // Declare these as state variables instead
    string[] TEST_TAGS;
    string[] TEST_EXTERNAL_LINKS;

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

        // Initialize the arrays here
        TEST_TAGS = new string[](2);
        TEST_TAGS[0] = "test";
        TEST_TAGS[1] = "demo";
        
        TEST_EXTERNAL_LINKS = new string[](1);
        TEST_EXTERNAL_LINKS[0] = "https://test.com";

        // Deploy RetroFund
        retroFund = new RetroFund(gnosisSafe, mainDAOMembers, subDAOMembers);
    }

    // Test proposal submission
    // Tests that a proposer can submit a new funding proposal
    // Verifies the proposal details are stored correctly
    function testSubmitProposal() public {
        vm.startPrank(proposer);
        uint256 proposalId = retroFund.submitProposal(
            START_IMAGE_HASH,
            REQUESTED_AMOUNT,
            ESTIMATED_DAYS,
            TEST_TITLE,
            TEST_DESCRIPTION,
            TEST_TAGS,
            TEST_DOCUMENTATION,
            TEST_EXTERNAL_LINKS
        );
        vm.stopPrank();

        RetroFund.Proposal memory proposal = retroFund.proposals(proposalId);
        assertEq(proposal.proposer, proposer);
        assertEq(proposal.requestedAmount, REQUESTED_AMOUNT);
        assertEq(proposal.initialVoting.startImageHash, START_IMAGE_HASH);
        assertEq(proposal.metadata.title, TEST_TITLE);
        assertEq(proposal.metadata.description, TEST_DESCRIPTION);
    }

    // Test main DAO voting
    // Verifies that votes are counted correctly and approval flags are set
    function testMainDAOVoting() public {
        // Submit proposal
        vm.prank(proposer);
        uint256 proposalId = retroFund.submitProposal(
            START_IMAGE_HASH,
            REQUESTED_AMOUNT,
            ESTIMATED_DAYS,
            TEST_TITLE,
            TEST_DESCRIPTION,
            TEST_TAGS,
            TEST_DOCUMENTATION,
            TEST_EXTERNAL_LINKS
        );

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
        uint256 proposalId = retroFund.submitProposal(
            START_IMAGE_HASH,
            REQUESTED_AMOUNT,
            ESTIMATED_DAYS,
            TEST_TITLE,
            TEST_DESCRIPTION,
            TEST_TAGS,
            TEST_DOCUMENTATION,
            TEST_EXTERNAL_LINKS
        );

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

    // Test failure cases

    function testFailureUnauthorizedVote() public {
        vm.prank(proposer);
        uint256 proposalId = retroFund.submitProposal(
            START_IMAGE_HASH,
            REQUESTED_AMOUNT,
            ESTIMATED_DAYS,
            TEST_TITLE,
            TEST_DESCRIPTION,
            TEST_TAGS,
            TEST_DOCUMENTATION,
            TEST_EXTERNAL_LINKS
        );

        // Try to vote as non-DAO member
        vm.prank(address(0x999));
        // The test will fail if the expected revert message doesn't match exactly with the actual revert message
        vm.expectRevert("Not a member of the main DAO");
        retroFund.voteFromMainDAO(proposalId, true);
    }

    function testFailureDoubleVote() public {
        vm.prank(proposer);
        uint256 proposalId = retroFund.submitProposal(
            START_IMAGE_HASH,
            REQUESTED_AMOUNT,
            ESTIMATED_DAYS,
            TEST_TITLE,
            TEST_DESCRIPTION,
            TEST_TAGS,
            TEST_DOCUMENTATION,
            TEST_EXTERNAL_LINKS
        );

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
        uint256 proposalId = retroFund.submitProposal(
            START_IMAGE_HASH,
            REQUESTED_AMOUNT,
            ESTIMATED_DAYS,
            TEST_TITLE,
            TEST_DESCRIPTION,
            TEST_TAGS,
            TEST_DOCUMENTATION,
            TEST_EXTERNAL_LINKS
        );

        // Try to declare completion before approval
        vm.prank(proposer);
        vm.expectRevert("revert: Proposal must be approved before completion");
        retroFund.declareProjectCompletion(proposalId, FINAL_IMAGE_HASH);
    }
}
