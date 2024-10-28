// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol"; // OpenZeppelin Ownable for admin roles
import "safe-smart-account/contracts/Safe.sol"; // 

contract RetroFund {
    uint256 constant public COOLDOWN_PERIOD = 72 hours;
    
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
        bool mainDAOApproved;      // New: tracks main DAO approval
        bool subDAOApproved;       // New: tracks subDAO approval
        // Main DAO votes
        uint256 mainDAOVotesInFavor;
        uint256 mainDAOVotesAgainst;
        // SubDAO votes
        uint256 subDAOVotesInFavor;
        uint256 subDAOVotesAgainst;
        // Completion votes
        bool mainDAOCompletionApproved;    // New: separate completion approvals
        bool subDAOCompletionApproved;     // New: separate completion approvals
        uint256 mainDAOCompletionVotesInFavor;
        uint256 mainDAOCompletionVotesAgainst;
        uint256 subDAOCompletionVotesInFavor;
        uint256 subDAOCompletionVotesAgainst;
        uint256 submissionTime;    // New: tracks when proposal was submitted
        bool isRejected;          // New: explicitly tracks rejection status
    }

    Proposal[] public proposals;
    address public gnosisSafe; // Gnosis Safe multisig wallet address
    mapping(address => bool) public trustedCommittee; // Multisig committee members
    mapping(address => bool) public mainDAOMembers;
    mapping(address => bool) public subDAOMembers;

    event ProposalSubmitted(uint256 proposalId, address proposer, uint256 amount, string startImageHash);
    event ProposalVoted(uint256 proposalId, address voter, bool inFavor);
    event ProposalCompleted(uint256 proposalId, string finalImageHash);
    event FundsReleased(uint256 proposalId, address proposer, uint256 amount);
    event CompletionVoted(uint256 proposalId, address voter, bool inFavor);
    event CompletionApproved(uint256 proposalId);
    event MainDAOVoted(uint256 proposalId, address voter, bool inFavor);
    event SubDAOVoted(uint256 proposalId, address voter, bool inFavor);
    event MainDAOCompletionVoted(uint256 proposalId, address voter, bool inFavor);
    event SubDAOCompletionVoted(uint256 proposalId, address voter, bool inFavor);
    event ProposalFinalized(uint256 indexed proposalId, bool approved);

    modifier onlyTrustedCommittee() {
        require(trustedCommittee[msg.sender], "Not part of trusted committee");
        _;
    }

    modifier onlyMainDAO() {
        require(mainDAOMembers[msg.sender], "Not part of main DAO");
        _;
    }

    modifier onlySubDAO() {
        require(subDAOMembers[msg.sender], "Not part of subDAO");
        _;
    }

    constructor(
        address _gnosisSafe,
        address[] memory _mainDAOMembers,
        address[] memory _subDAOMembers
    ) {
        gnosisSafe = _gnosisSafe;
        for (uint256 i = 0; i < _mainDAOMembers.length; i++) {
            mainDAOMembers[_mainDAOMembers[i]] = true;
        }
        for (uint256 i = 0; i < _subDAOMembers.length; i++) {
            subDAOMembers[_subDAOMembers[i]] = true;
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
            isRejected: false,
            submissionTime: block.timestamp,  // Add submission time
            completed: false,
            fundsReleased: false,
            finalImageHash: "",
            mainDAOApproved: false,
            subDAOApproved: false,
            mainDAOVotesInFavor: 0,
            mainDAOVotesAgainst: 0,
            subDAOVotesInFavor: 0,
            subDAOVotesAgainst: 0,
            mainDAOCompletionApproved: false,
            subDAOCompletionApproved: false,
            mainDAOCompletionVotesInFavor: 0,
            mainDAOCompletionVotesAgainst: 0,
            subDAOCompletionVotesInFavor: 0,
            subDAOCompletionVotesAgainst: 0
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
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.proposer == msg.sender, "Only proposer can declare completion");
        require(proposal.approved, "Proposal must be approved before completion");
        require(!proposal.isRejected, "Proposal was rejected");
        require(!proposal.completed, "Project already marked as completed");
        
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
    function releaseFunds(uint256 _proposalId) external {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.approved, "Proposal not approved");
        require(!proposal.isRejected, "Proposal was rejected");
        require(proposal.completed, "Project must be completed");
        require(!proposal.fundsReleased, "Funds already released");
        require(proposal.mainDAOCompletionApproved && proposal.subDAOCompletionApproved, 
                "Both Main DAO and SubDAO must approve completion");
        
        proposal.fundsReleased = true;

        // Execute fund release via Safe
        bool success = Safe(payable(gnosisSafe)).execTransactionFromModule(
            proposal.proposer,
            proposal.requestedAmount,
            "",  // indicates no additional data is sent with the transaction 
            Enum.Operation.Call
        );
        require(success, "Fund release transaction failed");

        emit FundsReleased(_proposalId, proposal.proposer, proposal.requestedAmount);
    }

    // Split voting functions for main DAO and subDAO
    function voteFromMainDAO(uint256 _proposalId, bool _inFavor) external onlyMainDAO {
        Proposal storage proposal = proposals[_proposalId];
        require(!isVotingPeriodEnded(_proposalId), "Voting period ended");
        require(!proposal.mainDAOApproved, "Main DAO already approved");
        require(!proposal.isRejected, "Proposal already rejected");
        
        if (_inFavor) {
            proposal.mainDAOVotesInFavor++;
        } else {
            proposal.mainDAOVotesAgainst++;
        }

        uint256 totalVotes = proposal.mainDAOVotesInFavor + proposal.mainDAOVotesAgainst;
        uint256 voteThreshold = 5; // Adjust as needed
        if (proposal.mainDAOVotesInFavor > proposal.mainDAOVotesAgainst && totalVotes >= voteThreshold) {
            proposal.mainDAOApproved = true;
        }

        emit MainDAOVoted(_proposalId, msg.sender, _inFavor);
    }

    function voteFromSubDAO(uint256 _proposalId, bool _inFavor) external onlySubDAO {
        Proposal storage proposal = proposals[_proposalId];
        require(!isVotingPeriodEnded(_proposalId), "Voting period ended");
        require(!proposal.subDAOApproved, "SubDAO already approved");
        require(!proposal.isRejected, "Proposal already rejected");
        
        if (_inFavor) {
            proposal.subDAOVotesInFavor++;
        } else {
            proposal.subDAOVotesAgainst++;
        }

        uint256 totalVotes = proposal.subDAOVotesInFavor + proposal.subDAOVotesAgainst;
        uint256 voteThreshold = 3; // Adjust as needed
        if (proposal.subDAOVotesInFavor > proposal.subDAOVotesAgainst && totalVotes >= voteThreshold) {
            proposal.subDAOApproved = true;
        }

        emit SubDAOVoted(_proposalId, msg.sender, _inFavor);
    }

    // Similar split for completion voting
    function voteOnCompletionFromMainDAO(uint256 _proposalId, bool _inFavor) external onlyMainDAO {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.completed, "Project must be marked as completed first");
        require(!proposal.mainDAOCompletionApproved, "Main DAO completion already approved");

        if (_inFavor) {
            proposal.mainDAOCompletionVotesInFavor++;
        } else {
            proposal.mainDAOCompletionVotesAgainst++;
        }

        if (proposal.mainDAOCompletionVotesInFavor > proposal.mainDAOCompletionVotesAgainst) {
            proposal.mainDAOCompletionApproved = true;
        }

        emit MainDAOCompletionVoted(_proposalId, msg.sender, _inFavor);
    }

    function voteOnCompletionFromSubDAO(uint256 _proposalId, bool _inFavor) external onlySubDAO {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.completed, "Project must be marked as completed first");
        require(!proposal.subDAOCompletionApproved, "SubDAO completion already approved");

        if (_inFavor) {
            proposal.subDAOCompletionVotesInFavor++;
        } else {
            proposal.subDAOCompletionVotesAgainst++;
        }

        if (proposal.subDAOCompletionVotesInFavor > proposal.subDAOCompletionVotesAgainst) {
            proposal.subDAOCompletionApproved = true;
        }

        emit SubDAOCompletionVoted(_proposalId, msg.sender, _inFavor);
    }

    // Add function to check if voting period has ended
    function isVotingPeriodEnded(uint256 _proposalId) public view returns (bool) {
        Proposal storage proposal = proposals[_proposalId];
        return block.timestamp >= proposal.submissionTime + COOLDOWN_PERIOD;
    }

    // Add function to finalize voting
    function finalizeVoting(uint256 _proposalId) external {
        Proposal storage proposal = proposals[_proposalId];
        require(!proposal.approved && !proposal.isRejected, "Proposal already finalized");
        require(isVotingPeriodEnded(_proposalId), "Cooldown period not ended");

        // Check both Main DAO and SubDAO votes
        bool mainDAOApproved = proposal.mainDAOVotesInFavor > proposal.mainDAOVotesAgainst;
        bool subDAOApproved = proposal.subDAOVotesInFavor > proposal.subDAOVotesAgainst;

        // Only approve if both DAOs approved
        if (mainDAOApproved && subDAOApproved) {
            proposal.approved = true;
        } else {
            proposal.isRejected = true;
        }

        emit ProposalFinalized(_proposalId, proposal.approved);
    }
}
