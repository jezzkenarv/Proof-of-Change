// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/// @title IProofOfChange Interface
/// @notice Interface for the ProofOfChange contract which manages proposal submissions and voting
/// @dev This interface defines all external functions and events for the ProofOfChange contract
interface IProofOfChange {
    // Structs
    /// @notice Stores voting data for the initial stage of a proposal
    /// @dev Used when a proposal is first submitted
    struct InitialVotingStage {
        string startImageHash; // IPFS hash of the initial project image
        bytes32 locationAttestationUID; // Add this line
        uint256 mainDAOVotesInFavor; // Number of main DAO votes supporting
        uint256 mainDAOVotesAgainst; // Number of main DAO votes against
        bool mainDAOApproved; // Whether main DAO has approved
        uint256 subDAOVotesInFavor; // Number of sub DAO votes supporting
        uint256 subDAOVotesAgainst; // Number of sub DAO votes against
        bool subDAOApproved; // Whether sub DAO has approved
        uint256 votingStartTime; // Timestamp when voting began
        bool stageApproved; // Whether this stage was approved
    }

    /// @notice Stores voting data for the progress stage of a proposal
    /// @dev Used at project midpoint to verify progress
    struct ProgressVotingStage {
        string progressImageHash; // IPFS hash of the progress update image
        uint256 mainDAOVotesInFavor; // Number of main DAO votes supporting
        uint256 mainDAOVotesAgainst; // Number of main DAO votes against
        bool mainDAOApproved; // Whether main DAO has approved
        uint256 subDAOVotesInFavor; // Number of sub DAO votes supporting
        uint256 subDAOVotesAgainst; // Number of sub DAO votes against
        bool subDAOApproved; // Whether sub DAO has approved
        uint256 votingStartTime; // Timestamp when voting began
        bool stageApproved; // Whether this stage was approved
    }

    /// @notice Stores voting data for the completion stage of a proposal
    /// @dev Used when project is marked as complete
    struct CompletionVotingStage {
        string finalImageHash; // IPFS hash of the final project image
        uint256 mainDAOVotesInFavor; // Number of main DAO votes supporting
        uint256 mainDAOVotesAgainst; // Number of main DAO votes against
        bool mainDAOApproved; // Whether main DAO has approved
        uint256 subDAOVotesInFavor; // Number of sub DAO votes supporting
        uint256 subDAOVotesAgainst; // Number of sub DAO votes against
        bool subDAOApproved; // Whether sub DAO has approved
        uint256 votingStartTime; // Timestamp when voting began
        bool stageApproved; // Whether this stage was approved
        bool completed; // Whether project is marked complete
    }

    /// @notice Main proposal struct containing all proposal data
    /// @dev Tracks the entire lifecycle of a proposal
    struct Proposal {
        address payable proposer; // Address that submitted the proposal
        uint256 requestedAmount; // Amount of funds requested
        uint256 submissionTime; // When proposal was submitted
        uint256 estimatedCompletionTime; // Expected completion timestamp
        uint256 midpointTime; // Midpoint check timestamp
        bool isRejected; // Whether proposal was rejected
        bool fundsReleased; // Whether funds were released
        ProposalMetadata metadata; // Add the metadata struct
        InitialVotingStage initialVoting; // Initial voting stage data
        ProgressVotingStage progressVoting; // Progress voting stage data
        CompletionVotingStage completionVoting; // Completion voting stage data
    }

    // Add a new struct for metadata
    struct ProposalMetadata {
        string title;           // Project title
        string description;     // Detailed project description
        string[] tags;         // Array of category tags
        string documentation;   // IPFS hash or URL to detailed documentation
        string[] externalLinks; // Array of additional relevant links
    }

    // Events
    /// @notice Emitted when a new proposal is submitted
    event ProposalSubmitted(uint256 proposalId, address proposer, uint256 amount, string startImageHash);
    /// @notice Emitted when a vote is cast on a proposal
    event ProposalVoted(uint256 proposalId, address voter, bool inFavor);
    /// @notice Emitted when a progress image is submitted
    event ProgressImageSubmitted(uint256 indexed proposalId, string progressImageHash);
    /// @notice Emitted when a project is marked as completed
    event ProposalCompleted(uint256 proposalId, string finalImageHash);
    /// @notice Emitted when funds are released to a proposer
    event FundsReleased(uint256 proposalId, address proposer, uint256 amount);
    /// @notice Emitted when a completion vote is cast
    event CompletionVoted(uint256 proposalId, address voter, bool inFavor);
    /// @notice Emitted when completion is approved
    event CompletionApproved(uint256 proposalId);
    /// @notice Emitted when main DAO casts a vote
    event MainDAOVoted(uint256 proposalId, address voter, bool inFavor);
    /// @notice Emitted when sub DAO casts a vote
    event SubDAOVoted(uint256 proposalId, address voter, bool inFavor);
    /// @notice Emitted when main DAO votes on completion
    event MainDAOCompletionVoted(uint256 proposalId, address voter, bool inFavor);
    /// @notice Emitted when sub DAO votes on completion
    event SubDAOCompletionVoted(uint256 proposalId, address voter, bool inFavor);
    /// @notice Emitted when a proposal is finalized
    event ProposalFinalized(uint256 indexed proposalId, bool approved);
    /// @notice Emitted when main DAO votes on progress
    event MainDAOProgressVoted(uint256 proposalId, address voter, bool inFavor);
    /// @notice Emitted when sub DAO votes on progress
    event SubDAOProgressVoted(uint256 proposalId, address voter, bool inFavor);
    /// @notice Emitted when a proposal is finalized
    event ProposalProgressFinalized(uint256 indexed proposalId, bool approved);
    /// @notice Emitted when a proposal is finalized
    event ProposalCompletionFinalized(uint256 indexed proposalId, bool approved);

    event ProposalMetadataAdded(
        uint256 indexed proposalId,
        string title,
        string description,
        string[] tags,
        string documentation,
        string[] externalLinks
    );

    // External Functions
    /// @notice Submit a new proposal
    /// @param startImageHash IPFS hash of the initial project image
    /// @param requestedAmount Amount of funds requested
    /// @param estimatedDays Estimated days until completion
    /// @param title Project title
    /// @param description Detailed project description
    /// @param tags Array of category tags
    /// @param documentation IPFS hash or URL to detailed documentation
    /// @param externalLinks Array of additional relevant links
    /// @return proposalId The ID of the newly created proposal
    function submitProposal(
        string memory startImageHash,
        uint256 requestedAmount,
        uint256 estimatedDays,
        string memory title,
        string memory description,
        string[] memory tags,
        string memory documentation,
        string[] memory externalLinks
    ) external returns (uint256);

    /// @notice Cast a vote from main DAO
    /// @param _proposalId The proposal being voted on
    /// @param _inFavor Whether the vote is in favor
    function voteFromMainDAO(uint256 _proposalId, bool _inFavor) external;

    /// @notice Cast a vote from sub DAO
    function voteFromSubDAO(uint256 _proposalId, bool _inFavor) external;

    /// @notice Cast a progress vote from main DAO
    function voteOnProgressFromMainDAO(uint256 _proposalId, bool _inFavor) external;

    /// @notice Cast a progress vote from sub DAO
    function voteOnProgressFromSubDAO(uint256 _proposalId, bool _inFavor) external;

    /// @notice Cast a completion vote from main DAO
    function voteOnCompletionFromMainDAO(uint256 _proposalId, bool _inFavor) external;

    /// @notice Cast a completion vote from sub DAO
    function voteOnCompletionFromSubDAO(uint256 _proposalId, bool _inFavor) external;

    /// @notice Mark a project as complete
    /// @param _proposalId The proposal being completed
    /// @param _finalImageHash IPFS hash of the final project image
    function declareProjectCompletion(uint256 _proposalId, string calldata _finalImageHash) external;

    /// @notice Finalize the voting process for a proposal
    function finalizeVoting(uint256 _proposalId) external;

    /// @notice Release funds to the proposer
    function releaseFunds(uint256 _proposalId) external;

    // View Functions
    /// @notice Check if voting period has ended
    /// @return bool Whether the voting period has ended
    function isVotingPeriodEnded(uint256 _proposalId) external view returns (bool);

    /// @notice Check if proposal is in progress voting window
    /// @return bool Whether the proposal is in progress voting window
    function isInProgressVotingWindow(uint256 _proposalId) external view returns (bool);

    /// @notice Check if proposal is in completion voting window
    /// @return bool Whether the proposal is in completion voting window
    function isInCompletionVotingWindow(uint256 _proposalId) external view returns (bool);

    // Public State Variables (as view functions)
    /// @notice Get the cooldown period duration
    function COOLDOWN_PERIOD() external view returns (uint256);

    /// @notice Get proposal details by ID
    function proposals(uint256) external view returns (Proposal memory);

    /// @notice Get the Gnosis Safe address
    function gnosisSafe() external view returns (address);

    /// @notice Check if address is main DAO member
    function mainDAOMembers(address) external view returns (bool);

    /// @notice Check if address is sub DAO member
    function subDAOMembers(address) external view returns (bool);

    // Add the hasVoted mapping to the interface
    function hasVoted(uint256 proposalId, address voter, uint8 stage) external view returns (bool);
}
