// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../src/RetroFund.sol";
import "safe-smart-account/contracts/Safe.sol";
import {ModuleManager} from "safe-smart-account/contracts/base/ModuleManager.sol";
import {Enum} from "safe-smart-account/contracts/libraries/Enum.sol";

contract RetroFundTest is Test {
    RetroFund public retroFund;
    Safe public gnosisSafe;
    address[] public committeeMembers;
    address public proposer;

    function setUp() public {
        gnosisSafe = new Safe();
        
        committeeMembers = new address[](3);
        committeeMembers[0] = address(this);
        committeeMembers[1] = address(0x1);
        committeeMembers[2] = address(0x2);

        retroFund = new RetroFund(address(gnosisSafe), committeeMembers);
        proposer = address(0x3);
        
        _setupGnosisSafeMock();
    }

    function _setupGnosisSafeMock() internal {
        vm.mockCall(
            address(gnosisSafe),
            abi.encodeWithSelector(ModuleManager.execTransactionFromModule.selector),
            abi.encode(true)
        );
    }

    function testSubmitProposal() public {
        vm.prank(proposer);
        retroFund.submitProposal("ipfs://startImageHash", 1 ether);

        (address payable _proposer, string memory startImageHash, uint256 requestedAmount, , , , , , , , , ) = retroFund.proposals(0);
        
        assertEq(_proposer, proposer);
        assertEq(startImageHash, "ipfs://startImageHash");
        assertEq(requestedAmount, 1 ether);
    }

    function testVoteOnProposal() public {
        _submitProposal();
        retroFund.voteOnProposal(0, true);

        (, , , bool approved, , , , uint256 votesInFavor, uint256 votesAgainst, , , ) = retroFund.proposals(0);
        
        assertEq(votesInFavor, 1);
        assertEq(votesAgainst, 0);
        assertFalse(approved);
    }

    function testDeclareProjectCompletion() public {
        _submitAndApproveProposal();

        vm.prank(proposer);
        retroFund.declareProjectCompletion(0, "ipfs://finalImageHash");

        (, , , , bool completed, , string memory finalImageHash, , , , , ) = retroFund.proposals(0);
        
        assertTrue(completed);
        assertEq(finalImageHash, "ipfs://finalImageHash");
    }

    function testVoteOnCompletion() public {
        _submitApproveAndCompleteProposal();

        retroFund.voteOnCompletion(0, true);

        (, , , , , , , , , uint256 completionVotesInFavor, , bool completionApproved) = retroFund.proposals(0);
        
        assertEq(completionVotesInFavor, 1);
        assertFalse(completionApproved);
    }

    function testReleaseFunds() public {
        _submitApproveAndCompleteProposal();
        _approveCompletion();

        retroFund.releaseFunds(0);

        _checkFundsReleased(0);
    }

    function _submitProposal() internal {
        vm.prank(proposer);
        retroFund.submitProposal("ipfs://startImageHash", 1 ether);
    }

    function _submitAndApproveProposal() internal {
        _submitProposal();
        for (uint i = 0; i < 3; i++) {
            vm.prank(committeeMembers[i]);
            retroFund.voteOnProposal(0, true);
        }
        // Add an extra vote to meet the threshold
        vm.prank(address(0x4));
        retroFund.voteOnProposal(0, true);
    }

    function _submitApproveAndCompleteProposal() internal {
        _submitAndApproveProposal();
        vm.prank(proposer);
        retroFund.declareProjectCompletion(0, "ipfs://finalImageHash");
    }

    function _approveCompletion() internal {
        for (uint i = 0; i < 2; i++) {
            vm.prank(committeeMembers[i]);
            retroFund.voteOnCompletion(0, true);
        }
    }

    function _checkFundsReleased(uint256 proposalId) internal {
        (, , , , , bool fundsReleased, , , , , , ) = retroFund.proposals(proposalId);
        assertTrue(fundsReleased);
    }
}
