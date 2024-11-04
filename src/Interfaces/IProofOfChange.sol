// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IProofOfChange {
    // Enums
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

    enum FunctionGroup {
        Voting,
        ProjectCreation,
        ProjectProgress,
        Membership,
        ProjectManagement,
        FundManagement
    }

    enum ProjectStatus {
        Active,
        Completed,
        Archived,
        Frozen
    }

    enum MediaActionType {
        Added,
        Updated,
        Verified
    }

    enum ProjectActionType {
        Created,
        StatusUpdated,
        Frozen,
        PhaseUpdated,
        Reassigned
    }

    // Events
    event VoteCast(bytes32 indexed attestationUID, address voter, MemberType memberType);
    event AttestationApproved(bytes32 indexed attestationUID);
    event VotingInitialized(bytes32 indexed attestationUID, uint256 votingEnds);
    event VoteFinalized(bytes32 indexed attestationUID, VoteResult result);
    event PhaseAttestationCreated(bytes32 indexed projectId, VoteType phase, bytes32 attestationUID);
    event PauseProposed(FunctionGroup indexed group, uint256 duration, bytes32 proposalId);
    event PauseVoteCast(bytes32 indexed proposalId, address indexed voter);
    event FunctionGroupPaused(FunctionGroup indexed group, uint256 pauseEnds);
    event FunctionGroupUnpaused(FunctionGroup indexed group);
    event EmergencyActionExecuted(address indexed executor, bytes32 indexed projectId, string action);
    event ProjectFrozen(bytes32 indexed projectId, uint256 duration, address indexed executor);
    event PhaseForceUpdated(bytes32 indexed projectId, VoteType newPhase, string reason);
    event ProjectReassigned(bytes32 indexed projectId, address indexed newProposer, address[] newValidators);
    event VotesUpdated(bytes32 indexed projectId, bytes32[] attestationUIDs);
    event MediaAction(
        bytes32 indexed projectId,
        VoteType indexed phase,
        string[] mediaTypes,
        string[] mediaData,
        uint256 timestamp,
        MediaActionType actionType
    );
    event MemberAction(
        address indexed member,
        MemberType memberType,
        MemberType previousType,
        uint256 regionId,
        bool isRemoval
    );
    event ProjectAction(
        bytes32 indexed projectId,
        address indexed actor,
        ProjectActionType actionType,
        string details
    );
    event MilestoneUpdated(
        bytes32 indexed projectId,
        VoteType indexed phase,
        string milestone,
        bool completed
    );

    // Add new events
    event ProjectFundingInitialized(
        bytes32 indexed projectId,
        uint256 totalAmount,
        uint256[] phaseAllocations
    );

    event PhaseFundsReleased(
        bytes32 indexed projectId,
        VoteType phase,
        address indexed recipient,
        uint256 amount,
        uint256 timestamp
    );

    // Errors
    error FunctionCurrentlyPaused(FunctionGroup group, uint256 pauseEnds);
    error UnauthorizedDAO();
    error UnauthorizedProposer();
    error InvalidPauseDuration();
    error PauseProposalNotFound();
    error AlreadyVotedForPause();
    error PauseProposalExpired();
    error InvalidVoteState();
    error InvalidAttestation();
    error AlreadyVoted();
    error SubDAOMemberNotFromRegion();
    error VotingPeriodNotEnded();
    error VoteAlreadyFinalized();
    error InvalidMediaData();
    error ProjectNotFound();
    error InvalidPhase();
    error MediaAlreadyExists();
    error InvalidDuration();
    error InvalidEmergencyAction();
    error InvalidAddresses();
    error InvalidVoteData();
    error MemberNotFound();
    error UnauthorizedOwner();
    error UnauthorizedAdmin();
    error InvalidStatusTransition();
    error ProjectNotCompletable();
    error InvalidMilestone();
    error OperationTimelocked(bytes32 operationId);
    error InvalidFundAllocation();
    error ProjectNotComplete();
    error PhaseNotApproved();
    error FundsAlreadyReleased();

    // Core functions
    function vote(bytes32 attestationUID, uint256 regionId, bool approve) external;
    function initializeVoting(bytes32 attestationUID, uint256 daoVotesNeeded, uint256 subDaoVotesNeeded) external;
    function finalizeVote(bytes32 attestationUID) external;
    function proposePause(FunctionGroup group, uint256 duration) external returns (bytes32);
    function emergencyPause(FunctionGroup group) external;
    function castPauseVote(bytes32 proposalId) external;

    // Add these new function declarations
    function getProjectDetails(bytes32 projectId) external view returns (
        string memory name,
        string memory description,
        string memory location,
        uint256 regionId,
        address proposer,
        VoteType currentPhase,
        bytes32 currentAttestationUID
    );
    
    function getUserProjects(address user) external view returns (bytes32[] memory);
    function addPhaseMedia(
        bytes32 projectId,
        VoteType phase,
        string[] calldata mediaTypes,
        string[] calldata mediaData,
        string calldata mediaDescription
    ) external;
    function createProject(ProjectCreationData calldata data) external returns (bytes32);
    function createPhaseAttestation(bytes32 projectId, VoteType phase) external returns (bytes32);
    function advanceToNextPhase(bytes32 projectId) external;

    // Add Vote struct
    struct Vote {
        uint256 daoVotesRequired;
        uint256 subDaoVotesRequired;
        uint256 daoVotesFor;
        uint256 daoVotesAgainst;
        uint256 subDaoVotesFor;
        uint256 subDaoVotesAgainst;
        uint256 votingEnds;
        mapping(address => bool) hasVoted;
        bool isFinalized;
        VoteResult result;
    }

    struct Media {
        string[] mediaTypes;
        string[] mediaData;
        uint256 timestamp;
        string description;
        bool verified;
    }

    struct ProjectCreationData {
        string name;
        string description;
        string location;
        uint256 regionId;
        string[] mediaTypes;
        string[] mediaData;
        string mediaDescription;
        uint256 expectedDuration;
        uint256 requestedFunds;
        uint256[] phaseAllocations;
    }

    // Membership management functions with access control notes
    /// @notice Adds a new DAO member
    /// @dev Should be restricted to contract owner/admin
    function addDAOMember(address member) external;

    /// @notice Adds a new SubDAO member for a specific region
    /// @dev Should be restricted to contract owner/admin
    function addSubDAOMember(address member, uint256 regionId) external;

    /// @notice Removes a DAO member
    /// @dev Should be restricted to contract owner/admin
    function removeDAOMember(address member) external;

    /// @notice Updates a member's type and region
    /// @dev Should be restricted to contract owner/admin
    function updateMember(address member, MemberType newType, uint256 regionId) external;

    // Add the function declarations in the interface
    function updateProjectStatus(bytes32 projectId, ProjectStatus newStatus) external;
    function getProjectStatus(bytes32 projectId) external view returns (ProjectStatus);

    // Add new function declarations
    function updateMilestone(
        bytes32 projectId,
        string calldata milestone,
        bool completed
    ) external;

    function isProjectDelayed(bytes32 projectId) external view returns (bool);

    function getPhaseProgress(
        bytes32 projectId,
        VoteType phase
    ) external view returns (
        uint256 startTime,
        uint256 targetEndTime,
        bool requiresMedia,
        bool isComplete,
        string[] memory milestones,
        uint256 completedMilestonesCount
    );
}
