// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IRetroFund {
        // Define voting-stage based structs
    struct InitialVotingStage {
        string startImageHash;
        // Main DAO votes
        uint256 mainDAOVotesInFavor;
        uint256 mainDAOVotesAgainst;
        bool mainDAOApproved;
        // Sub DAO votes
        uint256 subDAOVotesInFavor;
        uint256 subDAOVotesAgainst;
        bool subDAOApproved;
        // Timestamps and status
        uint256 votingStartTime;
        bool stageApproved;
    }

    struct ProgressVotingStage {
        string progressImageHash;
        // Main DAO votes
        uint256 mainDAOVotesInFavor;
        uint256 mainDAOVotesAgainst;
        bool mainDAOApproved;
        // Sub DAO votes
        uint256 subDAOVotesInFavor;
        uint256 subDAOVotesAgainst;
        bool subDAOApproved;
        // Timestamps and status
        uint256 votingStartTime;
        bool stageApproved;
    }

    struct CompletionVotingStage {
        string finalImageHash;
        // Main DAO votes
        uint256 mainDAOVotesInFavor;
        uint256 mainDAOVotesAgainst;
        bool mainDAOApproved;
        // Sub DAO votes
        uint256 subDAOVotesInFavor;
        uint256 subDAOVotesAgainst;
        bool subDAOApproved;
        // Timestamps and status
        uint256 votingStartTime;
        bool stageApproved;
        bool completed;
    }

    // Main Proposal struct that references the voting stage structs
    struct Proposal {
        address payable proposer;
        uint256 requestedAmount;
        uint256 submissionTime;
        uint256 estimatedCompletionTime;  // Added: time when project is expected to complete
        uint256 midpointTime;             // Added: automatically set to 50% of estimated time
        bool isRejected;
        bool fundsReleased;
        
        InitialVotingStage initialVoting;
        ProgressVotingStage progressVoting;
        CompletionVotingStage completionVoting;
    }
    // function isInProgressVotingWindow(uint256 _proposalId) external view returns (bool);
}