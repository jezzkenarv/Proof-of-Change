// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @title IProofOfChange
 * @notice Interface for the Proof of Change protocol, a decentralized project management and funding system
 * @dev Defines the core functionality for project attestations, voting, and fund management
 */
interface IProofOfChange {
    /*//////////////////////////////////////////////////////////////
                                ENUMS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Types of members in the system
    enum MemberType {
        NonMember,      // Not a member of any DAO
        SubDAOMember,   // Member of a regional sub-DAO
        DAOMember       // Member of the main DAO
    }
    
    /// @notice Project phases that require voting and attestation
    enum VoteType {
        Initial,        // Initial project proposal phase
        Progress,       // Mid-project progress phase
        Completion     // Final completion phase
    }
    
    /// @notice Possible outcomes for a vote
    enum VoteResult {
        Pending,        // Vote is still ongoing
        Approved,       // Vote passed successfully
        Rejected       // Vote failed to pass
    }

    /// @notice Groups of functions that can be paused independently
    enum FunctionGroup {
        Voting,             // Voting-related functions
        ProjectCreation,    // Project creation functions
        ProjectProgress,    // Project progress update functions
        Membership,         // Membership management functions
        ProjectManagement,  // General project management functions
        FundManagement     // Fund distribution functions
    }

    /// @notice Current status of a project
    enum ProjectStatus {
        Pending,    // Initial state, waiting for DAO review
        Active,     // Project approved and in progress
        Paused,     // Temporarily halted
        Completed,  // Successfully finished
        Rejected,   // Rejected by DAO
        Failed,     // Failed to meet objectives
        Cancelled   // Cancelled by proposer or DAO
    }

    /// @notice Types of actions that can be performed on a project
    enum ProjectActionType {
        Created,        // Project was created
        StatusUpdated,  // Project status was changed
        Frozen,         // Project was frozen
        PhaseUpdated,   // Project phase was updated
        Reassigned      // Project was reassigned to new proposer
    }

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Voting data for an attestation
    /// @dev Tracks both DAO and subDAO votes separately
    struct Vote {
        uint32 daoVotesRequired;      // Number of DAO votes needed
        uint32 subDaoVotesRequired;   // Number of subDAO votes needed
        uint32 daoVotesFor;           // Current DAO votes in favor
        uint32 subDaoVotesFor;        // Current subDAO votes in favor
        uint64 votingEnds;            // Timestamp when voting ends
        VoteResult result;            // Current vote result
        bool isFinalized;             // Whether vote has been finalized
        mapping(address => bool) hasVoted; // Track who has voted
    }

    /// @notice Data required to create a new project
    struct ProjectCreationData {
        string name;                    // Project name
        string description;             // Project description
        uint256 startDate;              // Planned start date
        uint256 duration;               // Expected duration in seconds
        uint256 requestedFunds;         // Amount of funds requested
        uint256 regionId;               // Geographic region ID
        bytes32 logbookAttestationUID;  // Initial logbook attestation
    }

    /// @notice Weights for different project phases
    /// @dev All weights must sum to 100
    struct PhaseWeights {
        uint256 initialWeight;      // Weight for initial phase (%)
        uint256 progressWeight;     // Weight for progress phase (%)
        uint256 completionWeight;   // Weight for completion phase (%)
        uint256 lastUpdated;        // Timestamp of last update
    }

    /// @notice Distribution of funds within a phase
    struct PhaseDistribution {
        uint256[] milestonePercentages;  // Percentage allocated to each milestone
        bool configured;                  // Whether distribution is set
    }

    /// @notice Proof of project state at a specific phase
    struct StateProof {
        bytes32 attestationUID;    // EAS attestation identifier
        bytes32 contentHash;       // Hash of content (IPFS CID)
        uint64 timestamp;          // When proof was submitted
        bool verified;             // Whether proof is verified
    }

    /// @notice Core project data structure
    struct Project {
        address proposer;          // Project creator address
        string name;               // Project name
        string description;        // Project description
        string location;           // Geographic location
        uint256 regionId;          // Region identifier
        uint256 requestedFunds;    // Total funds requested
        uint256 expectedDuration;  // Expected project duration
        ProjectStatus status;      // Current project status
        VoteType currentPhase;     // Current project phase
        uint64 createdAt;          // Creation timestamp
        uint64 startDate;          // Project start date
        bool fundsReleased;        // Whether funds were released
        mapping(VoteType => StateProof) stateProofs;      // Proofs by phase
        mapping(VoteType => PhaseProgress) phaseProgress;  // Progress by phase
    }

    /// @notice Tracks progress within a project phase
    struct PhaseProgress {
        string[] milestones;       // List of milestone identifiers
        mapping(string => bool) completedMilestones;  // Completion status
        uint64 startTime;          // Phase start time
        uint64 targetEndTime;      // Expected phase end time
        bool isComplete;           // Whether phase is complete
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a vote is cast on an attestation
    /// @param attestationUID The unique ID of the attestation being voted on
    /// @param voter The address of the voter
    /// @param memberType The type of member casting the vote
    event VoteCast(bytes32 indexed attestationUID, address voter, MemberType memberType);
    event AttestationApproved(bytes32 indexed attestationUID);
    event VotingInitialized(bytes32 indexed attestationUID, uint256 votingEnds);
    event VoteFinalized(bytes32 indexed attestationUID, VoteResult result);
    event PhaseAttestationCreated(bytes32 indexed projectId, VoteType phase, bytes32 attestationUID);
    event AttestationValidated(bytes32 indexed projectId, VoteType phase, bool success);
    event AttestationRevoked(bytes32 indexed projectId, VoteType phase, address revoker, uint256 timestamp);

    /// @notice Emitted when a project is created
    /// @param projectId Unique identifier of the project
    /// @param proposer Address of project creator
    /// @param name Name of the project
    /// @param regionId Region identifier
    /// @param requestedFunds Amount of funds requested
    /// @param timestamp Creation timestamp
    event ProjectCreated(
        bytes32 indexed projectId,
        address indexed proposer,
        string name,
        uint256 regionId,
        uint256 requestedFunds,
        uint256 timestamp
    );

    /// @notice Emitted when a project action occurs
    /// @param projectId Unique identifier of the project
    /// @param actor Address performing the action
    /// @param actionType Type of action performed
    /// @param details Additional action details
    event ProjectAction(
        bytes32 indexed projectId,
        address indexed actor,
        ProjectActionType actionType,
        string details
    );

    /// @notice Emitted when a project is frozen
    /// @param projectId The ID of the frozen project
    /// @param unfreezesAt Timestamp when the freeze expires
    event ProjectFrozen(bytes32 indexed projectId, uint256 unfreezesAt);

    /// @notice Emitted when a project is completed
    /// @param projectId The ID of the completed project
    /// @param timestamp When the project was completed
    event ProjectCompleted(bytes32 indexed projectId, uint256 timestamp);

    /// @notice Emitted when a project phase is forcibly updated
    /// @param projectId The ID of the affected project
    /// @param newPhase The phase being set
    /// @param reason Description of why the phase was forced
    event PhaseForceUpdated(bytes32 indexed projectId, VoteType newPhase, string reason);

    /// @notice Emitted when a project is reassigned to a new proposer
    /// @param projectId The ID of the reassigned project
    /// @param newProposer Address of the new proposer
    /// @param newValidators List of new validator addresses
    event ProjectReassigned(bytes32 indexed projectId, address indexed newProposer, address[] newValidators);

    /// @notice Emitted when a milestone's completion status changes
    /// @param projectId The ID of the project
    /// @param phase The phase containing the milestone
    /// @param milestone The milestone identifier
    /// @param completed Whether the milestone is now complete
    event MilestoneUpdated(bytes32 indexed projectId, VoteType indexed phase, string milestone, bool completed);

    /// @notice Emitted when progress is submitted for a project
    /// @param projectId The ID of the project
    /// @param logbookAttestationUID The attestation UID for the progress
    /// @param contentHash Hash of the progress content
    event ProgressSubmitted(bytes32 indexed projectId, bytes32 logbookAttestationUID, bytes32 contentHash);

    /// @notice Emitted when funds are released for a project phase
    /// @param projectId The ID of the project
    /// @param phase The phase funds are released for
    /// @param recipient Address receiving the funds
    /// @param amount Amount of funds released
    /// @param timestamp When the funds were released
    event PhaseFundsReleased(bytes32 indexed projectId, VoteType phase, address indexed recipient, uint256 amount, uint256 timestamp);

    /// @notice Emitted when funds are released with completion update
    /// @param projectId The ID of the project
    /// @param phase The phase being funded
    /// @param amount Amount released
    /// @param totalReleased Total funds released so far
    /// @param newCompletionPercentage Updated completion percentage
    event FundsReleased(bytes32 indexed projectId, VoteType phase, uint256 amount, uint256 totalReleased, uint256 newCompletionPercentage);

    event PhaseWeightsProposed(bytes32 indexed proposalId, uint256 initialWeight, uint256 progressWeight, uint256 completionWeight, address proposer);
    event PhaseWeightsUpdated(bytes32 indexed proposalId, uint256 initialWeight, uint256 progressWeight, uint256 completionWeight);
    event WeightVoteCast(bytes32 indexed proposalId, address voter, bool approved);
    event DistributionProposed(bytes32 indexed projectId, VoteType phase, uint256[] milestonePercentages, address proposer);
    event DistributionVoteCast(bytes32 indexed projectId, VoteType phase, address voter, bool approved);
    event DistributionConfigured(bytes32 indexed projectId, VoteType phase, uint256[] milestonePercentages);

    event PauseProposed(FunctionGroup indexed group, uint256 duration, bytes32 proposalId);
    event PauseVoteCast(bytes32 indexed proposalId, address indexed voter);
    event FunctionGroupPaused(FunctionGroup indexed group, uint256 pauseEnds);
    event FunctionGroupUnpaused(FunctionGroup indexed group);
    event EmergencyActionExecuted(address indexed executor, bytes32 indexed projectId, string action);
    event MemberAction(address indexed member, MemberType memberType, MemberType previousType, uint256 regionId, bool isRemoval);
    event VotesUpdated(bytes32 indexed projectId, bytes32[] attestationUIDs);
    event VotingPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event OperationQueued(bytes32 indexed operationId);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Function is currently paused
    /// @param group The function group that is paused
    /// @param pauseEnds Timestamp when the pause ends
    error FunctionCurrentlyPaused(FunctionGroup group, uint256 pauseEnds);
    error UnauthorizedDAO();
    error UnauthorizedProposer();
    error InvalidPauseDuration();
    error PauseProposalNotFound();
    error AlreadyVotedForPause();
    error PauseProposalExpired();
    error InvalidVoteState();
    error InvalidAttestation();
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
    error PhaseNotApproved();
    error FundsAlreadyReleased();
    error InvalidVotingPeriod();
    error TimelockNotExpired(bytes32 operationId, uint256 expiryTime);
    error UnauthorizedEmergencyAdmin();
    error InsufficientEmergencyApprovals(uint256 received, uint256 required);
    error UnauthorizedSubDAO();
    error ProjectNotActive();
    error InvalidFreezeDuration();
    error FundTransferFailed();
    error InvalidWeightTotal();
    error ProposalNotFound();
    error ProposalAlreadyExecuted();
    error AlreadyVoted();
    error InvalidPercentage();
    error ProjectNotComplete();
    error PhaseAlreadyStarted();
    error DistributionAlreadyConfigured();
    error DistributionNotConfigured();
    error InvalidMilestoneCount();
    error InvalidPercentageTotal();
    error UnauthorizedDistributionProposal();
    error UnauthorizedDistributionApproval();

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Cast a vote on an attestation
    /// @param attestationUID The attestation to vote on
    /// @param regionId The region ID for subDAO validation
    /// @param approve True to vote in favor, false against
    function vote(bytes32 attestationUID, uint256 regionId, bool approve) external;

    /// @notice Initialize voting parameters for an attestation
    /// @param attestationUID The attestation to initialize
    /// @param daoVotesNeeded Required number of DAO votes
    /// @param subDaoVotesNeeded Required number of subDAO votes
    function initializeVoting(bytes32 attestationUID, uint256 daoVotesNeeded, uint256 subDaoVotesNeeded) external;

    /// @notice Finalize a vote after voting period ends
    /// @param attestationUID The attestation to finalize
    function finalizeVote(bytes32 attestationUID) external;

    /// @notice Vote on proposed phase weight changes
    /// @param proposalId The weight proposal to vote on
    /// @param approve True to vote in favor, false against
    function voteOnPhaseWeights(bytes32 proposalId, bool approve) external;

    function createProject(ProjectCreationData calldata data) external payable returns (bytes32);
    function createPhaseAttestation(bytes32 projectId, VoteType phase) external returns (bytes32);
    function advanceToNextPhase(bytes32 projectId) external;
    function updateProjectStatus(bytes32 projectId, ProjectStatus newStatus) external;
    function updateMilestone(bytes32 projectId, string calldata milestone, bool completed) external;
    function submitProgress(bytes32 projectId, bytes32 logbookAttestationUID, string calldata contentCID) external;

    function releasePhaseFunds(bytes32 projectId, VoteType phase) external;
    function proposePhaseWeights(uint256 newInitialWeight, uint256 newProgressWeight, uint256 newCompletionWeight) external;

    function proposePause(FunctionGroup group, uint256 duration) external returns (bytes32);
    function emergencyPause(FunctionGroup group) external;
    function castPauseVote(bytes32 proposalId) external;
    function addDAOMember(address member) external;
    function addSubDAOMember(address member, uint256 regionId) external;
    function removeDAOMember(address member) external;
    function updateMember(address member, MemberType newType, uint256 regionId) external;
    function emergencyProjectAction(bytes32 projectId, uint256 freezeDuration) external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get detailed information about a project
    /// @param projectId The project to query
    /// @return Project details including proposer, name, status, etc.
    function getProjectDetails(bytes32 projectId) external view returns (
        address proposer,
        string memory name,
        string memory description,
        string memory location,
        uint256 regionId,
        VoteType currentPhase,
        ProjectStatus status,
        uint256 startDate,
        uint256 expectedDuration
    );

    /// @notice Get list of projects created by a user
    /// @param user The address to query
    /// @return Array of project IDs
    function getUserProjects(address user) external view returns (bytes32[] memory);

    function getProjectStatus(bytes32 projectId) external view returns (ProjectStatus);
    function isProjectDelayed(bytes32 projectId) external view returns (bool);
    function getPhaseProgress(bytes32 projectId, VoteType phase) external view returns (
        uint256 startTime,
        uint256 endTime,
        bool completed,
        bytes32 attestationUID,
        bytes32 contentHash
    );
    function getAttestationApprovalStatus(bytes32 attestationUID) external view returns (bool);
    function getProjectFinancials(bytes32 projectId) external view returns (
        uint256 totalRequested,
        uint256 initialPhaseAmount,
        uint256 progressPhaseAmount,
        uint256 completionPhaseAmount,
        bool[] memory phasesFunded
    );
    function calculateOverallCompletion(bytes32 projectId) external view returns (uint256);
    function getCurrentPhaseWeights(bytes32 projectId) external view returns (
        uint256 initialWeight,
        uint256 progressWeight,
        uint256 completionWeight
    );
}
