// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol"; // OpenZeppelin Ownable for admin roles
import "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol"; // Importing Gnosis Safe for multisig management

contract RetroFund {
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
    }

    Proposal[] public proposals;
    address public gnosisSafe; // Gnosis Safe multisig wallet address
    mapping(address => bool) public trustedCommittee; // Multisig committee members

    event ProposalSubmitted(uint256 proposalId, address proposer, uint256 amount, string startImageHash);
    event ProposalVoted(uint256 proposalId, address voter, bool inFavor);
    event ProposalCompleted(uint256 proposalId, string finalImageHash);
    event FundsReleased(uint256 proposalId, address proposer, uint256 amount);

    modifier onlyTrustedCommittee() {
        require(trustedCommittee[msg.sender], "Not part of trusted committee");
        _;
    }

    constructor(address _gnosisSafe, address[] memory _committeeMembers) {
        gnosisSafe = _gnosisSafe;
        // iterates through an array of addresses of committee members and for each address it sets a value in the trustedCommittee mapping with boolean values to true
        for (uint256 i = 0; i < _committeeMembers.length; i++) {
            trustedCommittee[_committeeMembers[i]] = true;
        }
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
            votesAgainst: 0
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

        // If majority votes in favor, approve the proposal
        if (proposal.votesInFavor > proposal.votesAgainst // && total votes are greater than some number) {
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

    // Releases the funds to a project proposer after their proposal has been approved and completed 
    function releaseFunds(uint256 _proposalId) external onlyTrustedCommittee {
        // retrieves the proposal from the proposals array using the provided _proposalId
        Proposal storage proposal = proposals[_proposalId];
        // checks that the project has been completed
        require(proposal.completed, "Project must be completed");
        // checks that the funds have not already been released
        require(!proposal.fundsReleased, "Funds already released");
        // marks funds as released to prevent double-spending 
        proposal.fundsReleased = true;
        
        // Execute fund release via Gnosis Safe
        // sends the requested amount of ETH to the project proposer's address
        GnosisSafe(gnosisSafe).execTransactionFromModule(
            proposal.proposer,
            proposal.requestedAmount,
            "",  // indicates no additional data is sent with the transaction 
            GnosisSafe.Operation.Call
        );

        emit FundsReleased(_proposalId, proposal.proposer, proposal.requestedAmount);
    }
}