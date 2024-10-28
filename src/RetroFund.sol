// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol"; // OpenZeppelin Ownable for admin roles
import "safe-smart-account/contracts/Safe.sol"; // Gnosis Safe
import "./IRetroFund.sol";

contract RetroFund is IRetroFund {
    uint256 constant public COOLDOWN_PERIOD = 72 hours;
    

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
    event MainDAOProgressVoted(uint256 proposalId, address voter, bool inFavor);
    event SubDAOProgressVoted(uint256 proposalId, address voter, bool inFavor);

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

    function submitProposal(
        string memory startImageHash,
        uint256 requestedAmount,
        uint256 estimatedDays    // Added: number of days estimated for completion
    ) external returns (uint256) {
        Proposal storage newProposal = proposals.push();
        
        // Basic Info
        newProposal.proposer = payable(msg.sender);
        newProposal.requestedAmount = requestedAmount;
        newProposal.submissionTime = block.timestamp;
        
        // Calculate timing checkpoints
        newProposal.estimatedCompletionTime = block.timestamp + (estimatedDays * 1 days);
        newProposal.midpointTime = block.timestamp + ((estimatedDays * 1 days) / 2);
        
        // Set initial voting stage
        newProposal.initialVoting.startImageHash = startImageHash;
        newProposal.initialVoting.votingStartTime = block.timestamp;
        
        // Image Data
        newProposal.progressVoting.progressImageHash = "";
        newProposal.completionVoting.finalImageHash = "";
        
        // Initial Voting
        newProposal.initialVoting.mainDAOApproved = false;
        newProposal.initialVoting.mainDAOVotesInFavor = 0;
        newProposal.initialVoting.mainDAOVotesAgainst = 0;
        newProposal.initialVoting.subDAOApproved = false;
        newProposal.initialVoting.subDAOVotesInFavor = 0;
        newProposal.initialVoting.subDAOVotesAgainst = 0;
        newProposal.initialVoting.stageApproved = false;
        newProposal.initialVoting.votingStartTime = block.timestamp;
        
        // Progress Voting
        newProposal.progressVoting.mainDAOApproved = false;
        newProposal.progressVoting.mainDAOVotesInFavor = 0;
        newProposal.progressVoting.mainDAOVotesAgainst = 0;
        newProposal.progressVoting.subDAOApproved = false;
        newProposal.progressVoting.subDAOVotesInFavor = 0;
        newProposal.progressVoting.subDAOVotesAgainst = 0;
        newProposal.progressVoting.stageApproved = false;
        newProposal.progressVoting.votingStartTime = block.timestamp;
        
        // Completion Voting
        newProposal.completionVoting.mainDAOApproved = false;
        newProposal.completionVoting.mainDAOVotesInFavor = 0;
        newProposal.completionVoting.mainDAOVotesAgainst = 0;
        newProposal.completionVoting.subDAOApproved = false;
        newProposal.completionVoting.subDAOVotesInFavor = 0;
        newProposal.completionVoting.subDAOVotesAgainst = 0;
        newProposal.completionVoting.stageApproved = false;
        newProposal.completionVoting.votingStartTime = block.timestamp;
        newProposal.completionVoting.completed = false;
        
        emit ProposalSubmitted(proposals.length - 1, msg.sender, requestedAmount, startImageHash);
        return proposals.length - 1;
    }

    // DAO members vote on the proposal
    function voteOnProposal(uint256 _proposalId, bool _inFavor) external onlyTrustedCommittee {
        // retrieves the proposal from the proposals array using the provided _proposalId
        Proposal storage proposal = proposals[_proposalId];
        // checks if the proposal has already been approved
        require(!proposal.initialVoting.stageApproved, "Proposal already approved");
        // if the proposal has not been approved, it increments the appropriate vote counter based on the _inFavor parameter
        if (_inFavor) {
            proposal.initialVoting.mainDAOVotesInFavor++;
        } else {
            proposal.initialVoting.mainDAOVotesAgainst++;
        }

        // If majority votes in favor and total votes exceed threshold, approve the proposal
        uint256 totalVotes = proposal.initialVoting.mainDAOVotesInFavor + proposal.initialVoting.mainDAOVotesAgainst;
        uint256 voteThreshold = 5; // Example threshold, adjust as needed
        if (proposal.initialVoting.mainDAOVotesInFavor > proposal.initialVoting.mainDAOVotesAgainst && totalVotes > voteThreshold) {
            proposal.initialVoting.mainDAOApproved = true;
        }

        emit ProposalVoted(_proposalId, msg.sender, _inFavor);
    }

    // dao votes again to vote and approve on project completion 

    // move logic from votes into a function for reusability 

    // allows a project proposer to mark their project as completed and submit the final image hash
    function declareProjectCompletion(uint256 _proposalId, string calldata _finalImageHash) external {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.proposer == msg.sender, "Only proposer can declare completion");
        require(proposal.initialVoting.stageApproved, "Proposal must be approved before completion");
        require(proposal.progressVoting.stageApproved, "Progress voting must be approved");
        require(!proposal.isRejected, "Proposal was rejected");
        require(!proposal.completionVoting.completed, "Project already marked as completed");
        
        proposal.completionVoting.completed = true;
        proposal.completionVoting.finalImageHash = _finalImageHash;
        proposal.completionVoting.votingStartTime = block.timestamp;

        emit ProposalCompleted(_proposalId, _finalImageHash);
    }

    function voteOnCompletion(uint256 _proposalId, bool _inFavor) external onlyTrustedCommittee {
        // retrieves the proposal from the proposals array using the provided _proposalId
        Proposal storage proposal = proposals[_proposalId];
        // ensures that the project has been marked as completed
        require(proposal.completionVoting.completed, "Project must be marked as completed first");
        // ensures that the completion has not already been approved
        require(!proposal.completionVoting.stageApproved, "Completion already approved");

        // increments the appropriate vote counter based on the _inFavor parameter
        if (_inFavor) {
            proposal.completionVoting.subDAOVotesInFavor++;
        } else {
            proposal.completionVoting.subDAOVotesAgainst++;
        }

        // If majority votes in favor, approve the completion
        if (proposal.completionVoting.subDAOVotesInFavor > proposal.completionVoting.subDAOVotesAgainst) {
            proposal.completionVoting.stageApproved = true;
            emit CompletionApproved(_proposalId);
        }

        emit CompletionVoted(_proposalId, msg.sender, _inFavor);
    }

    // Releases the funds to a project proposer after their proposal has been approved and completed 
    function releaseFunds(uint256 _proposalId) external {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.initialVoting.stageApproved, "Proposal not approved");
        require(!proposal.isRejected, "Proposal was rejected");
        require(proposal.completionVoting.completed, "Project must be completed");
        require(!proposal.fundsReleased, "Funds already released");
        require(proposal.completionVoting.mainDAOApproved && proposal.completionVoting.subDAOApproved, 
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
        require(!proposal.initialVoting.mainDAOApproved, "Main DAO already approved");
        require(!proposal.isRejected, "Proposal already rejected");
        
        if (_inFavor) {
            proposal.initialVoting.mainDAOVotesInFavor++;
        } else {
            proposal.initialVoting.mainDAOVotesAgainst++;
        }

        uint256 totalVotes = proposal.initialVoting.mainDAOVotesInFavor + 
                            proposal.initialVoting.mainDAOVotesAgainst;
        uint256 voteThreshold = 5; // Adjust as needed
        if (proposal.initialVoting.mainDAOVotesInFavor > proposal.initialVoting.mainDAOVotesAgainst && 
            totalVotes >= voteThreshold) {
            proposal.initialVoting.mainDAOApproved = true;
        }

        emit MainDAOVoted(_proposalId, msg.sender, _inFavor);
    }

    function voteFromSubDAO(uint256 _proposalId, bool _inFavor) external onlySubDAO {
        Proposal storage proposal = proposals[_proposalId];
        require(!isVotingPeriodEnded(_proposalId), "Voting period ended");
        require(!proposal.initialVoting.subDAOApproved, "SubDAO already approved");
        require(!proposal.isRejected, "Proposal already rejected");
        
        if (_inFavor) {
            proposal.initialVoting.subDAOVotesInFavor++;
        } else {
            proposal.initialVoting.subDAOVotesAgainst++;
        }

        uint256 totalVotes = proposal.initialVoting.subDAOVotesInFavor + 
                            proposal.initialVoting.subDAOVotesAgainst;
        uint256 voteThreshold = 3; // Adjust as needed
        if (proposal.initialVoting.subDAOVotesInFavor > proposal.initialVoting.subDAOVotesAgainst && 
            totalVotes >= voteThreshold) {
            proposal.initialVoting.subDAOApproved = true;
        }

        emit SubDAOVoted(_proposalId, msg.sender, _inFavor);
    }

    // Similar split for completion voting
    function voteOnCompletionFromMainDAO(uint256 _proposalId, bool _inFavor) external onlyMainDAO {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.progressVoting.stageApproved, "Progress voting must be approved first");
        require(proposal.completionVoting.completed, "Project must be marked as completed first");
        require(_isInCompletionVotingWindow(_proposalId), "Not in completion voting window");
        require(!proposal.completionVoting.mainDAOApproved, "Main DAO already voted on completion");

        if (_inFavor) {
            proposal.completionVoting.mainDAOVotesInFavor++;
        } else {
            proposal.completionVoting.mainDAOVotesAgainst++;
        }

        if (proposal.completionVoting.mainDAOVotesInFavor > proposal.completionVoting.mainDAOVotesAgainst) {
            proposal.completionVoting.mainDAOApproved = true;
        }

        emit MainDAOCompletionVoted(_proposalId, msg.sender, _inFavor);
    }

    function voteOnCompletionFromSubDAO(uint256 _proposalId, bool _inFavor) external onlySubDAO {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.progressVoting.stageApproved, "Progress voting must be approved first");
        require(proposal.completionVoting.completed, "Project must be marked as completed first");
        require(_isInCompletionVotingWindow(_proposalId), "Not in completion voting window");
        require(!proposal.completionVoting.subDAOApproved, "SubDAO already voted on completion");

        if (_inFavor) {
            proposal.completionVoting.subDAOVotesInFavor++;
        } else {
            proposal.completionVoting.subDAOVotesAgainst++;
        }

        if (proposal.completionVoting.subDAOVotesInFavor > proposal.completionVoting.subDAOVotesAgainst) {
            proposal.completionVoting.subDAOApproved = true;
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
        require(!proposal.initialVoting.stageApproved && !proposal.isRejected, "Proposal already finalized");
        require(isVotingPeriodEnded(_proposalId), "Cooldown period not ended");

        // Check both Main DAO and SubDAO votes
        bool mainDAOApproved = proposal.initialVoting.mainDAOVotesInFavor > 
                              proposal.initialVoting.mainDAOVotesAgainst;
        bool subDAOApproved = proposal.initialVoting.subDAOVotesInFavor > 
                             proposal.initialVoting.subDAOVotesAgainst;

        // Only approve if both DAOs approved
        if (mainDAOApproved && subDAOApproved) {
            proposal.initialVoting.stageApproved = true;
        } else {
            proposal.isRejected = true;
        }

        emit ProposalFinalized(_proposalId, proposal.initialVoting.stageApproved);
    }

    // Update progress voting functions
    function voteOnProgressFromMainDAO(uint256 _proposalId, bool _inFavor) external onlyMainDAO {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.initialVoting.stageApproved, "Initial voting must be approved first");
        require(_isInProgressVotingWindow(_proposalId), "Not in progress voting window");
        require(!proposal.progressVoting.mainDAOApproved, "Main DAO already voted on progress");
        require(!proposal.isRejected, "Proposal was rejected");

        if (_inFavor) {
            proposal.progressVoting.mainDAOVotesInFavor++;
        } else {
            proposal.progressVoting.mainDAOVotesAgainst++;
        }

        if (proposal.progressVoting.mainDAOVotesInFavor > proposal.progressVoting.mainDAOVotesAgainst) {
            proposal.progressVoting.mainDAOApproved = true;
        }

        emit MainDAOProgressVoted(_proposalId, msg.sender, _inFavor);
    }

    function voteOnProgressFromSubDAO(uint256 _proposalId, bool _inFavor) external onlySubDAO {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.initialVoting.stageApproved, "Initial voting must be approved first");
        require(_isInProgressVotingWindow(_proposalId), "Not in progress voting window");
        require(!proposal.progressVoting.subDAOApproved, "SubDAO already voted on progress");
        require(!proposal.isRejected, "Proposal was rejected");

        if (_inFavor) {
            proposal.progressVoting.subDAOVotesInFavor++;
        } else {
            proposal.progressVoting.subDAOVotesAgainst++;
        }

        if (proposal.progressVoting.subDAOVotesInFavor > proposal.progressVoting.subDAOVotesAgainst) {
            proposal.progressVoting.subDAOApproved = true;
        }

        emit SubDAOProgressVoted(_proposalId, msg.sender, _inFavor);
    }

    // Internal helper functions
    function _isInProgressVotingWindow(uint256 _proposalId) internal view returns (bool) {
        Proposal storage proposal = proposals[_proposalId];
        // Allow voting within ±3 days of midpoint
        uint256 windowBuffer = 3 days;
        return block.timestamp >= proposal.midpointTime - windowBuffer && 
               block.timestamp <= proposal.midpointTime + windowBuffer;
    }

    function _isInCompletionVotingWindow(uint256 _proposalId) internal view returns (bool) {
        Proposal storage proposal = proposals[_proposalId];
        // Allow voting within ±3 days of estimated completion
        uint256 windowBuffer = 3 days;
        return block.timestamp >= proposal.estimatedCompletionTime - windowBuffer && 
               block.timestamp <= proposal.estimatedCompletionTime + windowBuffer;
    }

    // External wrapper functions
    function isInProgressVotingWindow(uint256 _proposalId) external view returns (bool) {
        return _isInProgressVotingWindow(_proposalId);
    }

    function isInCompletionVotingWindow(uint256 _proposalId) external view returns (bool) {
        return _isInCompletionVotingWindow(_proposalId);
    }

}
