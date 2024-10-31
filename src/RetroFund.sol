// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "safe-smart-account/contracts/Safe.sol";
import {IRetroFund} from "./IRetroFund.sol";

contract RetroFund is IRetroFund {
    uint256 public constant override COOLDOWN_PERIOD = 72 hours;

    // Change from public to private to avoid getter function conflict
    Proposal[] private _proposals;
    address private _gnosisSafe;
    mapping(address => bool) private _mainDAOMembers;
    mapping(address => bool) private _subDAOMembers;

    // Update modifiers to use private variables

    modifier onlyMainDAO() {
        require(_mainDAOMembers[msg.sender], "Not part of main DAO");
        _;
    }

    modifier onlySubDAO() {
        require(_subDAOMembers[msg.sender], "Not part of subDAO");
        _;
    }

    // Add at contract level
    uint256 private _mainDAOmemberCount;
    uint256 private _subDAOmemberCount;

    // Update the mapping to track voting stages separately
    mapping(uint256 => mapping(address => mapping(uint8 => bool))) public hasVoted;

    // Add an enum to track voting stages (add at contract level)
    enum VotingStage {
        Initial,
        Progress,
        Completion
    }

    constructor(address gnosisSafe_, address[] memory mainDAOMembers_, address[] memory subDAOMembers_) {
        _gnosisSafe = gnosisSafe_;
        _mainDAOmemberCount = mainDAOMembers_.length;
        _subDAOmemberCount = subDAOMembers_.length;
        for (uint256 i = 0; i < mainDAOMembers_.length; i++) {
            _mainDAOMembers[mainDAOMembers_[i]] = true;
        }
        for (uint256 i = 0; i < subDAOMembers_.length; i++) {
            _subDAOMembers[subDAOMembers_[i]] = true;
        }
    }

    // allows users to submit new proposals to the system, which can then be voted on, completed, and potentially funded

    // creates a new proposal struct and adds it to the proposals array using push
    // sets the proposer to the address of the person calling the function (msg.sender)
    // uses input params to set the startImageHash and requestedAmount
    // initializes other fields with default values

    function submitProposal(string memory startImageHash, uint256 requestedAmount, uint256 estimatedDays)
        external
        returns (uint256)
    {
        Proposal storage newProposal = _proposals.push();

        // Basic Info
        newProposal.proposer = payable(msg.sender);
        newProposal.requestedAmount = requestedAmount;
        newProposal.submissionTime = block.timestamp;
        newProposal.estimatedCompletionTime = block.timestamp + (estimatedDays * 1 days);
        newProposal.midpointTime = block.timestamp + ((estimatedDays * 1 days) / 2);

        // Set initial voting stage
        newProposal.initialVoting.startImageHash = startImageHash;

        // Initialize all voting stages
        _initializeInitialVotingStage(newProposal.initialVoting);
        _initializeProgressVotingStage(newProposal.progressVoting);
        _initializeCompletionVotingStage(newProposal.completionVoting);

        // Additional completion-specific fields
        newProposal.completionVoting.completed = false;

        emit ProposalSubmitted(_proposals.length - 1, msg.sender, requestedAmount, startImageHash);
        return _proposals.length - 1;
    }

    function _initializeInitialVotingStage(InitialVotingStage storage stage) internal {
        stage.mainDAOApproved = false;
        stage.subDAOApproved = false;
        stage.stageApproved = false;
    }

    function _initializeProgressVotingStage(ProgressVotingStage storage stage) internal {
        stage.mainDAOApproved = false;
        stage.subDAOApproved = false;
        stage.stageApproved = false;
    }

    function _initializeCompletionVotingStage(CompletionVotingStage storage stage) internal {
        stage.mainDAOApproved = false;
        stage.subDAOApproved = false;
        stage.stageApproved = false;
        stage.completed = false;
    }

    // allows a project proposer to mark their project as completed and submit the final image hash
    function declareProjectCompletion(uint256 _proposalId, string calldata _finalImageHash) external {
        Proposal storage proposal = _proposals[_proposalId];
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

    // Split voting functions for main DAO and subDAO
    function voteFromMainDAO(uint256 _proposalId, bool _inFavor) external onlyMainDAO {
        Proposal storage proposal = _proposals[_proposalId];
        require(!isVotingPeriodEnded(_proposalId), "Voting period ended");
        require(!proposal.initialVoting.mainDAOApproved, "Main DAO already approved");
        require(!proposal.isRejected, "Proposal already rejected");

        // Add double-voting prevention
        require(!hasVoted[_proposalId][msg.sender][uint8(VotingStage.Initial)], "Already voted");
        hasVoted[_proposalId][msg.sender][uint8(VotingStage.Initial)] = true;

        if (_inFavor) {
            proposal.initialVoting.mainDAOVotesInFavor++;
        } else {
            proposal.initialVoting.mainDAOVotesAgainst++;
        }

        uint256 totalVotes = proposal.initialVoting.mainDAOVotesInFavor + proposal.initialVoting.mainDAOVotesAgainst;

        // Only set approval after all main DAO members have voted
        if (totalVotes == _mainDAOmemberCount) {
            proposal.initialVoting.mainDAOApproved =
                (proposal.initialVoting.mainDAOVotesInFavor > proposal.initialVoting.mainDAOVotesAgainst);
        }

        emit MainDAOVoted(_proposalId, msg.sender, _inFavor);
    }

    function voteFromSubDAO(uint256 _proposalId, bool _inFavor) external onlySubDAO {
        Proposal storage proposal = _proposals[_proposalId];
        require(!isVotingPeriodEnded(_proposalId), "Voting period ended");
        require(!proposal.initialVoting.subDAOApproved, "SubDAO already approved");
        require(!proposal.isRejected, "Proposal already rejected");

        // Add double-voting prevention
        require(!hasVoted[_proposalId][msg.sender][uint8(VotingStage.Initial)], "Already voted");
        hasVoted[_proposalId][msg.sender][uint8(VotingStage.Initial)] = true;

        if (_inFavor) {
            proposal.initialVoting.subDAOVotesInFavor++;
        } else {
            proposal.initialVoting.subDAOVotesAgainst++;
        }

        uint256 totalVotes = proposal.initialVoting.subDAOVotesInFavor + proposal.initialVoting.subDAOVotesAgainst;

        if (totalVotes == _subDAOmemberCount) {
            proposal.initialVoting.subDAOApproved = 
                (proposal.initialVoting.subDAOVotesInFavor > proposal.initialVoting.subDAOVotesAgainst);
        }

        emit SubDAOVoted(_proposalId, msg.sender, _inFavor);
    }

    // Update progress voting functions
    function voteOnProgressFromMainDAO(uint256 _proposalId, bool _inFavor) external onlyMainDAO {
        Proposal storage proposal = _proposals[_proposalId];
        require(proposal.initialVoting.stageApproved, "Initial voting must be approved first");
        require(isInProgressVotingWindow(_proposalId), "Not in progress voting window");
        require(!proposal.progressVoting.mainDAOApproved, "Main DAO already voted on progress");
        require(!proposal.isRejected, "Proposal was rejected");

        // Update double-voting prevention to use the Progress stage
        require(!hasVoted[_proposalId][msg.sender][uint8(VotingStage.Progress)], "Already voted");
        hasVoted[_proposalId][msg.sender][uint8(VotingStage.Progress)] = true;

        if (_inFavor) {
            proposal.progressVoting.mainDAOVotesInFavor++;
        } else {
            proposal.progressVoting.mainDAOVotesAgainst++;
        }

        uint256 totalVotes = proposal.progressVoting.mainDAOVotesInFavor + proposal.progressVoting.mainDAOVotesAgainst;

        if (totalVotes == _mainDAOmemberCount) {
            proposal.progressVoting.mainDAOApproved = 
                (proposal.progressVoting.mainDAOVotesInFavor > proposal.progressVoting.mainDAOVotesAgainst);
        }

        emit MainDAOProgressVoted(_proposalId, msg.sender, _inFavor);
    }

    function voteOnProgressFromSubDAO(uint256 _proposalId, bool _inFavor) external onlySubDAO {
        Proposal storage proposal = _proposals[_proposalId];
        require(proposal.initialVoting.stageApproved, "Initial voting must be approved first");
        require(isInProgressVotingWindow(_proposalId), "Not in progress voting window");
        require(!proposal.progressVoting.subDAOApproved, "SubDAO already voted on progress");
        require(!proposal.isRejected, "Proposal was rejected");

        // Update double-voting prevention to use the Progress stage
        require(!hasVoted[_proposalId][msg.sender][uint8(VotingStage.Progress)], "Already voted");
        hasVoted[_proposalId][msg.sender][uint8(VotingStage.Progress)] = true;

        if (_inFavor) {
            proposal.progressVoting.subDAOVotesInFavor++;
        } else {
            proposal.progressVoting.subDAOVotesAgainst++;
        }

        uint256 totalVotes = proposal.progressVoting.subDAOVotesInFavor + proposal.progressVoting.subDAOVotesAgainst;

        if (totalVotes == _subDAOmemberCount) {
            proposal.progressVoting.subDAOApproved = 
                (proposal.progressVoting.subDAOVotesInFavor > proposal.progressVoting.subDAOVotesAgainst);
        }

        emit SubDAOProgressVoted(_proposalId, msg.sender, _inFavor);
    }

    // Similar split for completion voting
    function voteOnCompletionFromMainDAO(uint256 _proposalId, bool _inFavor) external onlyMainDAO {
        Proposal storage proposal = _proposals[_proposalId];
        require(proposal.progressVoting.stageApproved, "Progress voting must be approved first");
        require(proposal.completionVoting.completed, "Project must be marked as completed first");
        require(isInCompletionVotingWindow(_proposalId), "Not in completion voting window");
        require(!proposal.completionVoting.mainDAOApproved, "Main DAO already voted on completion");

        // Add double-voting prevention
        require(!hasVoted[_proposalId][msg.sender][uint8(VotingStage.Completion)], "Already voted");
        hasVoted[_proposalId][msg.sender][uint8(VotingStage.Completion)] = true;

        if (_inFavor) {
            proposal.completionVoting.mainDAOVotesInFavor++;
        } else {
            proposal.completionVoting.mainDAOVotesAgainst++;
        }

        uint256 totalVotes = proposal.completionVoting.mainDAOVotesInFavor + proposal.completionVoting.mainDAOVotesAgainst;

        if (totalVotes == _mainDAOmemberCount) {
            proposal.completionVoting.mainDAOApproved = 
                (proposal.completionVoting.mainDAOVotesInFavor > proposal.completionVoting.mainDAOVotesAgainst);
        }

        emit MainDAOCompletionVoted(_proposalId, msg.sender, _inFavor);
    }

    function voteOnCompletionFromSubDAO(uint256 _proposalId, bool _inFavor) external onlySubDAO {
        Proposal storage proposal = _proposals[_proposalId];
        require(proposal.progressVoting.stageApproved, "Progress voting must be approved first");
        require(proposal.completionVoting.completed, "Project must be marked as completed first");
        require(isInCompletionVotingWindow(_proposalId), "Not in completion voting window");
        require(!proposal.completionVoting.subDAOApproved, "SubDAO already voted on completion");

        // Add double-voting prevention
        require(!hasVoted[_proposalId][msg.sender][uint8(VotingStage.Completion)], "Already voted");
        hasVoted[_proposalId][msg.sender][uint8(VotingStage.Completion)] = true;

        if (_inFavor) {
            proposal.completionVoting.subDAOVotesInFavor++;
        } else {
            proposal.completionVoting.subDAOVotesAgainst++;
        }

        uint256 totalVotes = proposal.completionVoting.subDAOVotesInFavor + proposal.completionVoting.subDAOVotesAgainst;

        if (totalVotes == _subDAOmemberCount) {
            proposal.completionVoting.subDAOApproved = 
                (proposal.completionVoting.subDAOVotesInFavor > proposal.completionVoting.subDAOVotesAgainst);
        }

        emit SubDAOCompletionVoted(_proposalId, msg.sender, _inFavor);
    }

    // Add function to finalize voting
    function finalizeVoting(uint256 _proposalId) external {
        Proposal storage proposal = _proposals[_proposalId];
        
        // Initial voting stage
        if (!proposal.initialVoting.stageApproved && !proposal.isRejected) {
            require(block.timestamp >= proposal.submissionTime + COOLDOWN_PERIOD, "Initial voting period not ended");
            
            bool mainDAOApproved = proposal.initialVoting.mainDAOVotesInFavor > proposal.initialVoting.mainDAOVotesAgainst;
            bool subDAOApproved = proposal.initialVoting.subDAOVotesInFavor > proposal.initialVoting.subDAOVotesAgainst;
            
            if (mainDAOApproved && subDAOApproved) {
                proposal.initialVoting.stageApproved = true;
            } else {
                proposal.isRejected = true;
            }
            
            emit ProposalFinalized(_proposalId, proposal.initialVoting.stageApproved);
            return;
        }

        // Progress voting stage
        if (proposal.initialVoting.stageApproved && !proposal.progressVoting.stageApproved) {
            require(block.timestamp >= proposal.midpointTime + COOLDOWN_PERIOD, "Progress voting period not ended");
            
            bool mainDAOApproved = proposal.progressVoting.mainDAOVotesInFavor > proposal.progressVoting.mainDAOVotesAgainst;
            bool subDAOApproved = proposal.progressVoting.subDAOVotesInFavor > proposal.progressVoting.subDAOVotesAgainst;
            
            if (mainDAOApproved && subDAOApproved) {
                proposal.progressVoting.stageApproved = true;
            } else {
                proposal.isRejected = true;
            }
            
            emit ProposalProgressFinalized(_proposalId, proposal.progressVoting.stageApproved);
            return;
        }

        // Completion voting stage
        if (proposal.progressVoting.stageApproved && !proposal.completionVoting.stageApproved && proposal.completionVoting.completed) {
            require(block.timestamp >= proposal.completionVoting.votingStartTime + COOLDOWN_PERIOD, "Completion voting period not ended");
            
            bool mainDAOApproved = proposal.completionVoting.mainDAOVotesInFavor > proposal.completionVoting.mainDAOVotesAgainst;
            bool subDAOApproved = proposal.completionVoting.subDAOVotesInFavor > proposal.completionVoting.subDAOVotesAgainst;
            
            if (mainDAOApproved && subDAOApproved) {
                proposal.completionVoting.stageApproved = true;
            } else {
                proposal.isRejected = true;
            }
            
            emit ProposalCompletionFinalized(_proposalId, proposal.completionVoting.stageApproved);
            return;
        }

        revert("No voting stage to finalize");
    }

    // Releases the funds to a project proposer after their proposal has been approved and completed
    function releaseFunds(uint256 _proposalId) external {
        Proposal storage proposal = _proposals[_proposalId];
        require(proposal.initialVoting.stageApproved, "Proposal not approved");
        require(!proposal.isRejected, "Proposal was rejected");
        require(proposal.completionVoting.completed, "Project must be completed");
        require(!proposal.fundsReleased, "Funds already released");
        require(
            proposal.completionVoting.mainDAOApproved && proposal.completionVoting.subDAOApproved,
            "Both Main DAO and SubDAO must approve completion"
        );

        proposal.fundsReleased = true;

        // Execute fund release via Safe
        bool success = Safe(payable(_gnosisSafe)).execTransactionFromModule(
            proposal.proposer,
            proposal.requestedAmount,
            "", // indicates no additional data is sent with the transaction
            Enum.Operation.Call
        );
        require(success, "Fund release transaction failed");

        emit FundsReleased(_proposalId, proposal.proposer, proposal.requestedAmount);
    }

    // Add function to check if voting period has ended
    function isVotingPeriodEnded(uint256 _proposalId) public view returns (bool) {
        Proposal storage proposal = _proposals[_proposalId];
        return block.timestamp >= proposal.submissionTime + COOLDOWN_PERIOD;
    }

    // External wrapper functions
    function isInProgressVotingWindow(uint256 _proposalId) public view returns (bool) {
        Proposal storage proposal = _proposals[_proposalId];
        uint256 windowBuffer = 3 days;
        return block.timestamp >= proposal.midpointTime - windowBuffer
            && block.timestamp <= proposal.midpointTime + windowBuffer;
    }

    function isInCompletionVotingWindow(uint256 _proposalId) public view returns (bool) {
        Proposal storage proposal = _proposals[_proposalId];
        uint256 windowBuffer = 3 days;
        return block.timestamp >= proposal.estimatedCompletionTime - windowBuffer
            && block.timestamp <= proposal.estimatedCompletionTime + windowBuffer;
    }

    // Add getter functions to match interface
    function proposals(uint256 index) external view override returns (Proposal memory) {
        return _proposals[index];
    }

    function gnosisSafe() external view override returns (address) {
        return _gnosisSafe;
    }

    function mainDAOMembers(address member) external view override returns (bool) {
        return _mainDAOMembers[member];
    }

    function subDAOMembers(address member) external view override returns (bool) {
        return _subDAOMembers[member];
    }
}
