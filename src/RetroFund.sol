// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol"; // OpenZeppelin Ownable for admin roles
import "@aragon/os/contracts/apps/AragonApp.sol"; // Import Aragon DAO contract

contract RetroFund is AragonApp {
    struct Proposal {
        address payable proposer;
        string startImageHash; // IPFS hash for starting image (commitment)
        uint256 requestedAmount;
        bool approved;
        bool completed;
        bool fundsReleased;
        string finalImageHash; // IPFS hash for final image
        uint256 votesInFavor;
        uint256 votesAgainst;
        uint256 completionVotesInFavor;
        uint256 completionVotesAgainst;
        bool completionApproved;
    }

    Proposal[] public proposals;
    address public aragonDao; // Aragon DAO address instead of Gnosis Safe
    mapping(address => bool) public trustedCommittee; // Multisig committee members

    event ProposalSubmitted(uint256 proposalId, address proposer, uint256 amount, string startImageHash);
    event ProposalVoted(uint256 proposalId, address voter, bool inFavor);
    event ProposalCompleted(uint256 proposalId, string finalImageHash);
    event FundsReleased(uint256 proposalId, address proposer, uint256 amount);
    event CompletionVoted(uint256 proposalId, address voter, bool inFavor);
    event CompletionApproved(uint256 proposalId);

    bytes32 public constant TRUSTED_COMMITTEE_ROLE = keccak256("TRUSTED_COMMITTEE_ROLE");

    constructor(address _aragonDao) {
        aragonDao = _aragonDao;
    }

    // allows users to submit new proposals to the system, which can then be voted on, completed, and potentially funded    

    // creates a new proposal struct and adds it to the proposals array using push 
    // sets the proposer to the address of the person calling the function (msg.sender)
    // uses input params to set the startImageHash and requestedAmount
    // initializes other fields with default values 

    function submitProposal(string calldata _startImageHash, uint256 _requestedAmount) external {
        proposals.push(Proposal({
            proposer: payable(msg.sender),
            startImageHash: _startImageHash,
            requestedAmount: _requestedAmount,
            approved: false,
            completed: false,
            fundsReleased: false,
            finalImageHash: "",
            votesInFavor: 0,
            votesAgainst: 0,
            completionVotesInFavor: 0,
            completionVotesAgainst: 0,
            completionApproved: false
        }));
        
        emit ProposalSubmitted(proposals.length - 1, msg.sender, _requestedAmount, _startImageHash);
    }

    // DAO members vote on the proposal
    function voteOnProposal(uint256 _proposalId, bool _inFavor) external onlyTrustedCommittee {
        // retrieves the proposal from the proposals array using the provided _proposalId
        Proposal storage proposal = proposals[_proposalId];
        // checks if the proposal has already been approved
        require(!proposal.approved, "Proposal already approved");
        // if the proposal has not been approved, it increments the appropriate vote counter based on the _inFavor parameter
        if (_inFavor) {
            proposal.votesInFavor++;
        } else {
            proposal.votesAgainst++;
        }

        // If majority votes in favor and total votes exceed threshold, approve the proposal
        uint256 totalVotes = proposal.votesInFavor + proposal.votesAgainst;
        uint256 voteThreshold = 5; // Example threshold, adjust as needed
        if (proposal.votesInFavor > proposal.votesAgainst && totalVotes > voteThreshold) {
            proposal.approved = true;
        }

        emit ProposalVoted(_proposalId, msg.sender, _inFavor);
    }

    // dao votes again to vote and approve on project completion 

    // move logic from votes into a function for reusability 

    // allows a project proposer to mark their project as completed and submit the final image hash
    function declareProjectCompletion(uint256 _proposalId, string calldata _finalImageHash) external {
        // retrieves the proposal from the proposals array using the provided _proposalId
        Proposal storage proposal = proposals[_proposalId];
        // ensures that only the original proposer can declare the completion of the project
        require(proposal.proposer == msg.sender, "Only proposer can declare completion");
        // ensures that the proposal has been approved by the DAO members
        require(proposal.approved, "Proposal must be approved before completion");
        // ensures that the project has not already been marked as completed
        require(!proposal.completed, "Project already marked as completed");
        // if all checks pass, it updates the proposal: sets completed to true and sets the finalImageHash to the provided _finalImageHash
        proposal.completed = true;
        proposal.finalImageHash = _finalImageHash;

        emit ProposalCompleted(_proposalId, _finalImageHash);
    }

    function voteOnCompletion(uint256 _proposalId, bool _inFavor) external onlyTrustedCommittee {
        // retrieves the proposal from the proposals array using the provided _proposalId
        Proposal storage proposal = proposals[_proposalId];
        // ensures that the project has been marked as completed
        require(proposal.completed, "Project must be marked as completed first");
        // ensures that the completion has not already been approved
        require(!proposal.completionApproved, "Completion already approved");

        // increments the appropriate vote counter based on the _inFavor parameter
        if (_inFavor) {
            proposal.completionVotesInFavor++;
        } else {
            proposal.completionVotesAgainst++;
        }

        // If majority votes in favor, approve the completion
        if (proposal.completionVotesInFavor > proposal.completionVotesAgainst) {
            proposal.completionApproved = true;
            emit CompletionApproved(_proposalId);
        }

        emit CompletionVoted(_proposalId, msg.sender, _inFavor);
    }

    // Releases the funds to a project proposer after their proposal has been approved and completed 
    function releaseFunds(uint256 _proposalId) external onlyTrustedCommittee {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.completed, "Project must be completed");
        require(!proposal.fundsReleased, "Funds already released");
        require(proposal.completionApproved, "Completion must be approved");
        
        proposal.fundsReleased = true;

        // Execute fund release via Aragon DAO
        bool success = aragonDao.call(
            abi.encodeWithSignature(
                "transferFunds(address,uint256)",
                proposal.proposer,
                proposal.requestedAmount
            )
        );
        require(success, "Fund release transaction failed");

        emit FundsReleased(_proposalId, proposal.proposer, proposal.requestedAmount);
    }
}
