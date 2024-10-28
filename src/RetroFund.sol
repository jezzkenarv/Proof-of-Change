// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol"; // OpenZeppelin Ownable for admin roles
import "safe-smart-account/contracts/Safe.sol"; // 

contract RetroFund {
    uint256 constant public COOLDOWN_PERIOD = 72 hours;
    
    // Define structs separately
    struct ImageData {
        string startImageHash;
        string finalImageHash;
    }

    struct InitialVoting {
        bool approved;
        uint256 votesInFavor;
        uint256 votesAgainst;
    }

    struct MainDAOData {
        bool approved;
        uint256 votesInFavor;
        uint256 votesAgainst;
        bool completionApproved;
        uint256 completionVotesInFavor;
        uint256 completionVotesAgainst;
    }

    struct SubDAOData {
        bool approved;
        uint256 votesInFavor;
        uint256 votesAgainst;
        bool completionApproved;
        uint256 completionVotesInFavor;
        uint256 completionVotesAgainst;
    }

    struct CompletionData {
        bool completed;
        bool completionApproved;
        uint256 completionVotesInFavor;
        uint256 completionVotesAgainst;
    }

    // Main Proposal struct that references the other structs
    struct Proposal {
        // Basic Info
        address payable proposer;
        uint256 requestedAmount;
        uint256 submissionTime;
        bool isRejected;
        bool fundsReleased;
        
        // Structured Data
        ImageData imageData;
        InitialVoting initialVoting;
        MainDAOData mainDAO;
        SubDAOData subDAO;
        CompletionData completion;
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
        Proposal storage newProposal = proposals.push();
        
        // Basic Info
        newProposal.proposer = payable(msg.sender);
        newProposal.requestedAmount = _requestedAmount;
        newProposal.submissionTime = block.timestamp;
        newProposal.isRejected = false;
        newProposal.fundsReleased = false;
        
        // Image Data
        newProposal.imageData.startImageHash = _startImageHash;
        newProposal.imageData.finalImageHash = "";
        
        // Initial Voting
        newProposal.initialVoting.approved = false;
        newProposal.initialVoting.votesInFavor = 0;
        newProposal.initialVoting.votesAgainst = 0;
        
        // Main DAO
        newProposal.mainDAO.approved = false;
        newProposal.mainDAO.votesInFavor = 0;
        newProposal.mainDAO.votesAgainst = 0;
        newProposal.mainDAO.completionApproved = false;
        newProposal.mainDAO.completionVotesInFavor = 0;
        newProposal.mainDAO.completionVotesAgainst = 0;
        
        // Sub DAO
        newProposal.subDAO.approved = false;
        newProposal.subDAO.votesInFavor = 0;
        newProposal.subDAO.votesAgainst = 0;
        newProposal.subDAO.completionApproved = false;
        newProposal.subDAO.completionVotesInFavor = 0;
        newProposal.subDAO.completionVotesAgainst = 0;
        
        // Completion
        newProposal.completion.completed = false;
        newProposal.completion.completionApproved = false;
        newProposal.completion.completionVotesInFavor = 0;
        newProposal.completion.completionVotesAgainst = 0;
        
        emit ProposalSubmitted(proposals.length - 1, msg.sender, _requestedAmount, _startImageHash);
    }

    // DAO members vote on the proposal
    function voteOnProposal(uint256 _proposalId, bool _inFavor) external onlyTrustedCommittee {
        // retrieves the proposal from the proposals array using the provided _proposalId
        Proposal storage proposal = proposals[_proposalId];
        // checks if the proposal has already been approved
        require(!proposal.initialVoting.approved, "Proposal already approved");
        // if the proposal has not been approved, it increments the appropriate vote counter based on the _inFavor parameter
        if (_inFavor) {
            proposal.initialVoting.votesInFavor++;
        } else {
            proposal.initialVoting.votesAgainst++;
        }

        // If majority votes in favor and total votes exceed threshold, approve the proposal
        uint256 totalVotes = proposal.initialVoting.votesInFavor + proposal.initialVoting.votesAgainst;
        uint256 voteThreshold = 5; // Example threshold, adjust as needed
        if (proposal.initialVoting.votesInFavor > proposal.initialVoting.votesAgainst && totalVotes > voteThreshold) {
            proposal.initialVoting.approved = true;
        }

        emit ProposalVoted(_proposalId, msg.sender, _inFavor);
    }

    // dao votes again to vote and approve on project completion 

    // move logic from votes into a function for reusability 

    // allows a project proposer to mark their project as completed and submit the final image hash
    function declareProjectCompletion(uint256 _proposalId, string calldata _finalImageHash) external {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.proposer == msg.sender, "Only proposer can declare completion");
        require(proposal.initialVoting.approved, "Proposal must be approved before completion");
        require(!proposal.isRejected, "Proposal was rejected");
        require(!proposal.completion.completed, "Project already marked as completed");
        
        proposal.completion.completed = true;
        proposal.imageData.finalImageHash = _finalImageHash;

        emit ProposalCompleted(_proposalId, _finalImageHash);
    }

    function voteOnCompletion(uint256 _proposalId, bool _inFavor) external onlyTrustedCommittee {
        // retrieves the proposal from the proposals array using the provided _proposalId
        Proposal storage proposal = proposals[_proposalId];
        // ensures that the project has been marked as completed
        require(proposal.completion.completed, "Project must be marked as completed first");
        // ensures that the completion has not already been approved
        require(!proposal.completion.completionApproved, "Completion already approved");

        // increments the appropriate vote counter based on the _inFavor parameter
        if (_inFavor) {
            proposal.completion.completionVotesInFavor++;
        } else {
            proposal.completion.completionVotesAgainst++;
        }

        // If majority votes in favor, approve the completion
        if (proposal.completion.completionVotesInFavor > proposal.completion.completionVotesAgainst) {
            proposal.completion.completionApproved = true;
            emit CompletionApproved(_proposalId);
        }

        emit CompletionVoted(_proposalId, msg.sender, _inFavor);
    }

    // Releases the funds to a project proposer after their proposal has been approved and completed 
    function releaseFunds(uint256 _proposalId) external {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.initialVoting.approved, "Proposal not approved");
        require(!proposal.isRejected, "Proposal was rejected");
        require(proposal.completion.completed, "Project must be completed");
        require(!proposal.fundsReleased, "Funds already released");
        require(proposal.mainDAO.completionApproved && proposal.subDAO.completionApproved, 
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
        require(!proposal.mainDAO.approved, "Main DAO already approved");
        require(!proposal.isRejected, "Proposal already rejected");
        
        if (_inFavor) {
            proposal.mainDAO.votesInFavor++;
        } else {
            proposal.mainDAO.votesAgainst++;
        }

        uint256 totalVotes = proposal.mainDAO.votesInFavor + proposal.mainDAO.votesAgainst;
        uint256 voteThreshold = 5; // Adjust as needed
        if (proposal.mainDAO.votesInFavor > proposal.mainDAO.votesAgainst && totalVotes >= voteThreshold) {
            proposal.mainDAO.approved = true;
        }

        emit MainDAOVoted(_proposalId, msg.sender, _inFavor);
    }

    function voteFromSubDAO(uint256 _proposalId, bool _inFavor) external onlySubDAO {
        Proposal storage proposal = proposals[_proposalId];
        require(!isVotingPeriodEnded(_proposalId), "Voting period ended");
        require(!proposal.subDAO.approved, "SubDAO already approved");
        require(!proposal.isRejected, "Proposal already rejected");
        
        if (_inFavor) {
            proposal.subDAO.votesInFavor++;
        } else {
            proposal.subDAO.votesAgainst++;
        }

        uint256 totalVotes = proposal.subDAO.votesInFavor + proposal.subDAO.votesAgainst;
        uint256 voteThreshold = 3; // Adjust as needed
        if (proposal.subDAO.votesInFavor > proposal.subDAO.votesAgainst && totalVotes >= voteThreshold) {
            proposal.subDAO.approved = true;
        }

        emit SubDAOVoted(_proposalId, msg.sender, _inFavor);
    }

    // Similar split for completion voting
    function voteOnCompletionFromMainDAO(uint256 _proposalId, bool _inFavor) external onlyMainDAO {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.completion.completed, "Project must be marked as completed first");
        require(!proposal.mainDAO.completionApproved, "Main DAO completion already approved");

        if (_inFavor) {
            proposal.mainDAO.completionVotesInFavor++;
        } else {
            proposal.mainDAO.completionVotesAgainst++;
        }

        if (proposal.mainDAO.completionVotesInFavor > proposal.mainDAO.completionVotesAgainst) {
            proposal.mainDAO.completionApproved = true;
        }

        emit MainDAOCompletionVoted(_proposalId, msg.sender, _inFavor);
    }

    function voteOnCompletionFromSubDAO(uint256 _proposalId, bool _inFavor) external onlySubDAO {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.completion.completed, "Project must be marked as completed first");
        require(!proposal.subDAO.completionApproved, "SubDAO completion already approved");

        if (_inFavor) {
            proposal.subDAO.completionVotesInFavor++;
        } else {
            proposal.subDAO.completionVotesAgainst++;
        }

        if (proposal.subDAO.completionVotesInFavor > proposal.subDAO.completionVotesAgainst) {
            proposal.subDAO.completionApproved = true;
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
        require(!proposal.initialVoting.approved && !proposal.isRejected, "Proposal already finalized");
        require(isVotingPeriodEnded(_proposalId), "Cooldown period not ended");

        // Check both Main DAO and SubDAO votes
        bool mainDAOApproved = proposal.mainDAO.votesInFavor > proposal.mainDAO.votesAgainst;
        bool subDAOApproved = proposal.subDAO.votesInFavor > proposal.subDAO.votesAgainst;

        // Only approve if both DAOs approved
        if (mainDAOApproved && subDAOApproved) {
            proposal.initialVoting.approved = true;
        } else {
            proposal.isRejected = true;
        }

        emit ProposalFinalized(_proposalId, proposal.initialVoting.approved);
    }
}
