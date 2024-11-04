// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/// @title IProofOfChange Interface
/// @notice Interface for the ProofOfChange contract which manages proposal submissions and voting
/// @dev This interface defines all external functions and events for the ProofOfChange contract
interface IProofOfChange {
    // Add new enums
    enum MemberType {
        NonMember,
        SubDAOMember,
        DAOMember
    }
    
    enum VoteType {
        Initial,
        Progress,
        Completion
    }
    
    enum VoteResult {
        Pending,
        Approved,
        Rejected
    }

    // Add new structs
    struct Media {
        string[] mediaTypes;
        string[] mediaData;
        uint256 timestamp;
        string description;
        bool verified;
    }

    // Add new events
    event VoteCast(bytes32 indexed attestationUID, address voter, MemberType memberType);
    event AttestationApproved(bytes32 indexed attestationUID);
    event MemberAdded(address member, MemberType memberType, uint256 regionId);
    event VotingInitialized(bytes32 indexed attestationUID, uint256 votingEnds);
    event VoteFinalized(bytes32 indexed attestationUID, VoteResult result);
    event ProjectCreated(
        bytes32 indexed projectId,
        address indexed proposer,
        string name,
        uint256 regionId
    );
    event PhaseAttestationCreated(
        bytes32 indexed projectId,
        VoteType phase,
        bytes32 attestationUID
    );
    event MediaAdded(
        bytes32 indexed projectId,
        VoteType phase,
        string[] mediaTypes,
        string[] mediaData,
        uint256 timestamp
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

    /// @notice Vote on a proposal
    /// @param attestationUID The attestation UID
    /// @param regionId The region ID
    /// @param approve Whether the vote is in favor
    function vote(bytes32 attestationUID, uint256 regionId, bool approve) external;

    /// @notice Initialize voting
    /// @param attestationUID The attestation UID
    /// @param daoVotesNeeded The number of DAO votes needed
    /// @param subDaoVotesNeeded The number of sub DAO votes needed
    function initializeVoting(bytes32 attestationUID, uint256 daoVotesNeeded, uint256 subDaoVotesNeeded) external;

    /// @notice Check if a proposal is approved
    /// @param attestationUID The attestation UID
    /// @return bool Whether the proposal is approved
    function isApproved(bytes32 attestationUID) external view returns (bool);

    /// @notice Add a DAO member
    /// @param member The member address
    function addDAOMember(address member) external;

    /// @notice Add a sub DAO member
    /// @param member The member address
    /// @param regionId The region ID
    function addSubDAOMember(address member, uint256 regionId) external;

    /// @notice Finalize a vote
    /// @param attestationUID The attestation UID
    function finalizeVote(bytes32 attestationUID) external;

    /// @notice Create a project
    /// @param name The project name
    /// @param description The project description
    /// @param location The project location
    /// @param regionId The region ID
    /// @param initialMediaTypes The initial media types
    /// @param initialMediaData The initial media data
    /// @param mediaDescription The media description
    /// @return projectId The project ID
    function createProject(
        string calldata name,
        string calldata description,
        string calldata location,
        uint256 regionId,
        string[] calldata initialMediaTypes,
        string[] calldata initialMediaData,
        string calldata mediaDescription
    ) external returns (bytes32);

    /// @notice Create a phase attestation
    /// @param projectId The project ID
    /// @param phase The phase
    /// @return attestationUID The attestation UID
    function createPhaseAttestation(bytes32 projectId, VoteType phase) external returns (bytes32);

    /// @notice Advance to the next phase
    /// @param projectId The project ID
    function advanceToNextPhase(bytes32 projectId) external;

    /// @notice Get project details
    /// @param projectId The project ID
    /// @return name The project name
    /// @return description The project description
    /// @return location The project location
    /// @return regionId The region ID
    /// @return proposer The proposer address
    /// @return currentPhase The current phase
    /// @return currentAttestationUID The current attestation UID
    function getProjectDetails(bytes32 projectId) external view returns (
        string memory name,
        string memory description,
        string memory location,
        uint256 regionId,
        address proposer,
        VoteType currentPhase,
        bytes32 currentAttestationUID
    );

    /// @notice Get user projects
    /// @param user The user address
    /// @return projectIds The project IDs
    function getUserProjects(address user) external view returns (bytes32[] memory);

    /// @notice Add phase media
    /// @param projectId The project ID
    /// @param phase The phase
    /// @param mediaTypes The media types
    /// @param mediaData The media data
    /// @param mediaDescription The media description
    function addPhaseMedia(
        bytes32 projectId,
        VoteType phase,
        string[] calldata mediaTypes,
        string[] calldata mediaData,
        string calldata mediaDescription
    ) external;

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

    // /// @notice Get proposal details by ID
    // function proposals(uint256) external view returns (Proposal memory);

    /// @notice Get the Gnosis Safe address
    function gnosisSafe() external view returns (address);

    /// @notice Check if address is main DAO member
    function mainDAOMembers(address) external view returns (bool);

    /// @notice Check if address is sub DAO member
    function subDAOMembers(address) external view returns (bool);

    // Add the hasVoted mapping to the interface
    function hasVoted(uint256 proposalId, address voter, uint8 stage) external view returns (bool);

    // Add constants
    /// @notice Get the location schema
    function LOCATION_SCHEMA() external view returns (bytes32);

    /// @notice Get the voting period
    function VOTING_PERIOD() external view returns (uint256);
}
