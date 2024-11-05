// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Constants and Immutables
// Core Data Structures
// State Variables
// Constructor
// Modifiers
// Core Project Lifecycle Functions
// Voting and Attestation Functions
// Fund Management
// Media and Milestone Management
// Emergency and Administrative Functions
// View Functions

import {IEAS, Attestation, AttestationRequest, AttestationRequestData} from "@eas/IEAS.sol";
import {SchemaResolver} from "@eas/resolver/SchemaResolver.sol";
import {IProofOfChange} from "./Interfaces/IProofOfChange.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/// @title Proof of Change
/// @notice A contract for managing decentralized project attestations and voting
/// @dev Implements EAS schema resolver and reentrancy protection
contract ProofOfChange is SchemaResolver, IProofOfChange, ReentrancyGuard {
    using Strings for uint256;

    // SECTION 1: Constants and Immutables
    
    /// @notice Schema hash for location-based attestations
    bytes32 public constant LOCATION_SCHEMA = 0xb16fa048b0d597f5a821747eba64efa4762ee5143e9a80600d0005386edfc995;
    
    /// @notice Duration for emergency pauses (3 days)
    uint256 public constant EMERGENCY_PAUSE_DURATION = 3 days;
    
    /// @notice Duration for standard pauses (14 days)
    uint256 public constant STANDARD_PAUSE_DURATION = 14 days;
    
    /// @notice Required delay for timelocked operations (24 hours)
    uint256 public constant TIMELOCK_PERIOD = 24 hours;
    
    /// @notice Minimum approvals needed for emergency actions
    uint256 public constant EMERGENCY_THRESHOLD = 2;

    /// @notice EAS contract interface
    IEAS private immutable eas;
    
    /// @notice Minimum votes required for pause actions (66% of initial DAO)
    uint256 public immutable minimumPauseVotes;

    // SECTION 2: Core Data Structures

    /// @notice Project data structure
    /// @dev Contains all project-related information and mappings
    struct Project {
        // Basic Information
        address proposer;
        string name;
        string description;
        string location;
        uint256 regionId;
        
        // Status and Phase
        IProofOfChange.VoteType currentPhase;
        ProjectStatus status;
        bool hasInitialMedia;
        
        // Timing and Funds
        uint256 createdAt;
        uint256 startDate;
        uint256 expectedDuration;
        uint256 requestedFunds;
        bool fundsReleased;
        
        // Phase-specific Data
        mapping(IProofOfChange.VoteType => Media) media;
        mapping(IProofOfChange.VoteType => bytes32) attestationUIDs;
        mapping(IProofOfChange.VoteType => PhaseProgress) phaseProgress;
        mapping(IProofOfChange.VoteType => uint256) phaseAllocations;
    }

    /// @notice Pause voting configuration
    struct PauseVoting {
        uint256 votesRequired;
        uint256 votesReceived;
        uint256 duration;
        uint256 proposedAt;
        bool executed;
        mapping(address => bool) hasVoted;
    }

    /// @notice Pause state configuration
    struct PauseConfig {
        bool isPaused;
        uint256 pauseEnds;
        bool requiresVoting;
    }

    /// @notice Phase progress tracking
    struct PhaseProgress {
        uint256 startTime;
        uint256 targetEndTime;
        bool requiresMedia;
        bool isComplete;
        string[] milestones;
        mapping(string => bool) completedMilestones;
    }

    /// @notice Weight proposal structure
    struct WeightProposal {
        uint256 initialWeight;
        uint256 progressWeight;
        uint256 completionWeight;
        uint256 votesReceived;
        uint256 votesRequired;
        uint256 proposedAt;
        bool executed;
        bool exists;
        mapping(address => bool) hasVoted;
    }

    /// @notice Project progress tracking
    struct ProjectProgress {
        uint256 completionPercentage;
        uint256 totalFundsReleased;
        mapping(IProofOfChange.VoteType => uint256) phaseCompletionPercentages;
    }

    // SECTION 3: State Variables

    /// @notice Mapping of attestation votes
    mapping(bytes32 => Vote) public attestationVotes;
    
    /// @notice Mapping of member types by address
    mapping(address => IProofOfChange.MemberType) public members;
    
    /// @notice Mapping of subDAO membership by region
    mapping(uint256 => mapping(address => bool)) public regionSubDAOMembers;
    
    /// @notice Mapping of projects by ID
    mapping(bytes32 => Project) public projects;
    
    /// @notice Mapping of project IDs by user address
    mapping(address => bytes32[]) public userProjects;
    
    /// @notice Mapping of pause configurations by function group
    mapping(IProofOfChange.FunctionGroup => PauseConfig) public pauseConfigs;
    
    /// @notice Mapping of pause votes by proposal ID
    mapping(bytes32 => PauseVoting) public pauseVotes;
    
    /// @notice Duration of voting periods in days (configurable by DAO)
    uint256 public votingPeriod;
    
    /// @notice Mapping of project freeze end times
    mapping(bytes32 => uint256) public projectFrozenUntil;
    
    /// @notice Mapping of pending operation timestamps
    mapping(bytes32 => uint256) public pendingOperations;
    
    /// @notice Mapping of emergency approval status
    mapping(bytes32 => mapping(address => bool)) public emergencyApprovals;
    
    /// @notice List of emergency admin addresses
    address[] public emergencyAdmins;
    
    /// @notice Mapping of phase fund release status
    mapping(bytes32 => mapping(IProofOfChange.VoteType => bool)) public phaseFundsReleased;

    /// @notice Phase weights configuration
    PhaseWeights public phaseWeights;

    /// @notice Weight proposals
    mapping(bytes32 => WeightProposal) public weightProposals;

    /// @notice Project progress tracking
    mapping(bytes32 => ProjectProgress) public projectProgress;

    // SECTION 4: Constructor

    /// @notice Contract constructor
    /// @param easRegistry Address of the EAS registry
    /// @param initialDAOMembers Initial list of DAO members
    constructor(address easRegistry, address[] memory initialDAOMembers) SchemaResolver(IEAS(easRegistry)) {
        eas = IEAS(easRegistry);
        minimumPauseVotes = (initialDAOMembers.length * 2) / 3; // 66% of initial DAO members
        votingPeriod = 7 days; // Set initial voting period to 7 days
        
        for (uint256 i = 0; i < initialDAOMembers.length; i++) {
            members[initialDAOMembers[i]] = IProofOfChange.MemberType.DAOMember;
            emergencyAdmins.push(initialDAOMembers[i]);
        }

        // Set default weights
        phaseWeights = PhaseWeights({
            initialWeight: 20,      // 20%
            progressWeight: 50,     // 50%
            completionWeight: 30,   // 30%
            lastUpdated: block.timestamp
        });
    }

    // SECTION 5: Modifiers

    /// @notice Ensures function is not paused
    /// @dev Automatically unpauses if pause duration has expired
    /// @param group The function group to check pause status for
    modifier whenNotPaused(IProofOfChange.FunctionGroup group) {
        PauseConfig storage config = pauseConfigs[group];
        
        if (config.isPaused) {
            // Check if pause has expired and can be automatically lifted
            if (config.pauseEnds != 0 && block.timestamp >= config.pauseEnds) {
                _unpause(group);
            } else {
                revert IProofOfChange.FunctionCurrentlyPaused(group, config.pauseEnds);
            }
        }
        _;
    }

    /// @notice Implements timelock delay for sensitive operations
    /// @dev Operations must be queued for TIMELOCK_PERIOD before execution
    /// @param operationId Unique identifier for the operation
    modifier timeLocked(bytes32 operationId) {
        // If operation not queued, queue it and revert
        if (pendingOperations[operationId] == 0) {
            pendingOperations[operationId] = block.timestamp + TIMELOCK_PERIOD;
            emit OperationQueued(operationId);
            revert IProofOfChange.OperationTimelocked(operationId);
        }

        // If operation is queued but timelock not expired, revert
        if (block.timestamp < pendingOperations[operationId]) {
            revert IProofOfChange.TimelockNotExpired(
                operationId,
                pendingOperations[operationId]
            );
        }

        // Clear timelock and proceed
        delete pendingOperations[operationId];
        _;
    }

    /// @notice Requires multiple emergency admin approvals
    /// @dev Enforces EMERGENCY_THRESHOLD number of approvals
    /// @param operationId Unique identifier for the emergency operation
    modifier requiresEmergencyConsensus(bytes32 operationId) {
        // Verify caller is emergency admin
        if (!isEmergencyAdmin(msg.sender)) {
            revert IProofOfChange.UnauthorizedEmergencyAdmin();
        }

        // Record approval
        emergencyApprovals[operationId][msg.sender] = true;
        
        // Count total approvals
        uint256 approvalCount = 0;
        for (uint256 i = 0; i < emergencyAdmins.length; i++) {
            if (emergencyApprovals[operationId][emergencyAdmins[i]]) {
                approvalCount++;
            }
        }
        
        // Verify threshold met
        if (approvalCount < EMERGENCY_THRESHOLD) {
            revert IProofOfChange.InsufficientEmergencyApprovals(
                approvalCount,
                EMERGENCY_THRESHOLD
            );
        }
        _;
    }

    /// @notice Ensures caller is a DAO member
    modifier onlyDAOMember() {
        if (members[msg.sender] != IProofOfChange.MemberType.DAOMember) {
            revert IProofOfChange.UnauthorizedDAO();
        }
        _;
    }

    /// @notice Ensures caller is a subDAO member for specific region
    /// @param regionId The region ID to check membership for
    modifier onlySubDAOMember(uint256 regionId) {
        if (!regionSubDAOMembers[regionId][msg.sender]) {
            revert IProofOfChange.UnauthorizedSubDAO();
        }
        _;
    }

    /// @notice Ensures project exists and is active
    /// @param projectId The project ID to validate
    modifier validProject(bytes32 projectId) {
        Project storage project = projects[projectId];
        if (project.proposer == address(0)) {
            revert IProofOfChange.ProjectNotFound();
        }
        if (project.status != ProjectStatus.Active) {
            revert IProofOfChange.ProjectNotActive();
        }
        _;
    }

    /// @notice Ensures project is not frozen
    /// @param projectId The project ID to check freeze status
    modifier notFrozen(bytes32 projectId) {
        if (block.timestamp < projectFrozenUntil[projectId]) {
            revert ProjectNotActive();
        }
        _;
    }

    // SECTION 6: Core Project Lifecycle Functions

    /// @notice Creates a new project with initial funding and media data
    /// @dev Initializes project in Initial phase with required documentation
    /// @param data The project creation data including media and funding details
    /// @return projectId The unique identifier of the created project
    function createProject(
        ProjectCreationData calldata data
    ) external nonReentrant whenNotPaused(IProofOfChange.FunctionGroup.ProjectManagement) returns (bytes32) {
        // Validate media data
        if (data.mediaTypes.length == 0 || data.mediaTypes.length != data.mediaData.length) {
            revert IProofOfChange.InvalidMediaData();
        }

        // Validate project constraints
        if (!_validateFundAllocation(data.phaseAllocations, data.requestedFunds)) {
            revert InvalidFundAllocation();
        }
        if (data.expectedDuration < 1 days || data.expectedDuration > 365 days) {
            revert InvalidDuration();
        }
        
        // Generate unique project ID
        bytes32 projectId = keccak256(
            abi.encodePacked(
                data.name,
                block.timestamp,
                msg.sender
            )
        );

        // Initialize project components
        _createProjectData(
            projectId, 
            data.name, 
            data.description, 
            data.location, 
            data.regionId,
            data.expectedDuration,
            data.requestedFunds,
            data.phaseAllocations
        );

        // Set up initial phase requirements
        string[] memory initialMilestones = new string[](1);
        initialMilestones[0] = "Submit initial documentation";
        _initializePhaseProgress(
            projectId,
            IProofOfChange.VoteType.Initial,
            7 days,
            true,
            initialMilestones
        );

        // Add initial media content
        _addInitialMedia(
            projectId,
            data.mediaTypes,
            data.mediaData,
            data.mediaDescription
        );

        // Record project ownership and emit creation event
        userProjects[msg.sender].push(projectId);
        emit ProjectAction(
            projectId, 
            msg.sender, 
            ProjectActionType.Created, 
            data.name
        );

        // Initialize project attestation
        createPhaseAttestation(projectId, IProofOfChange.VoteType.Initial);

        return projectId;
    }

    /// @notice Initializes core project data and funding allocations
    /// @dev Private function called during project creation
    function _createProjectData(
        bytes32 projectId,
        string calldata name,
        string calldata description,
        string calldata location,
        uint256 regionId,
        uint256 expectedDuration,
        uint256 requestedFunds,
        uint256[] calldata phaseAllocations
    ) private {
        Project storage newProject = projects[projectId];
        
        // Set basic project information
        newProject.name = name;
        newProject.description = description;
        newProject.location = location;
        newProject.regionId = regionId;
        newProject.proposer = msg.sender;
        
        // Set project parameters
        newProject.currentPhase = IProofOfChange.VoteType.Initial;
        newProject.expectedDuration = expectedDuration;
        newProject.requestedFunds = requestedFunds;
        newProject.startDate = block.timestamp;
        newProject.fundsReleased = false;

        // Initialize phase funding allocations
        for (uint256 i = 0; i < phaseAllocations.length; i++) {
            newProject.phaseAllocations[IProofOfChange.VoteType(i)] = phaseAllocations[i];
        }

        emit ProjectFundingInitialized(
            projectId, 
            requestedFunds, 
            phaseAllocations
        );
    }

    /// @notice Advances project to next phase after current phase approval
    /// @dev Progression: Initial -> Progress -> Completion
    /// @param projectId The ID of the project to advance
    function advanceToNextPhase(
        bytes32 projectId
    ) external 
        nonReentrant 
        whenNotPaused(IProofOfChange.FunctionGroup.ProjectManagement)
        notFrozen(projectId)
    {
        // Validate project and authorization
        Project storage project = projects[projectId];
        if (project.proposer == address(0)) revert IProofOfChange.ProjectNotFound();
        if (msg.sender != project.proposer) revert IProofOfChange.UnauthorizedProposer();

        // Verify current phase completion
        bytes32 currentAttestationUID = project.attestationUIDs[project.currentPhase];
        Vote storage currentVote = attestationVotes[currentAttestationUID];
        if (currentVote.result != IProofOfChange.VoteResult.Approved) {
            revert IProofOfChange.PhaseNotApproved();
        }

        // Progress to next phase
        if (project.currentPhase == IProofOfChange.VoteType.Initial) {
            project.currentPhase = IProofOfChange.VoteType.Progress;
        } else if (project.currentPhase == IProofOfChange.VoteType.Progress) {
            project.currentPhase = IProofOfChange.VoteType.Completion;
        } else {
            revert IProofOfChange.InvalidPhase();
        }

        // Initialize new phase attestation
        createPhaseAttestation(projectId, project.currentPhase);
    }

    /// @notice Updates the status of a project
    /// @dev Only DAO members can update status, with specific transition rules
    /// @param projectId The ID of the project to update
    /// @param newStatus The new status to set
    function updateProjectStatus(
        bytes32 projectId, 
        ProjectStatus newStatus
    ) external 
        whenNotPaused(IProofOfChange.FunctionGroup.ProjectManagement)
        notFrozen(projectId)
    {
        // Validate caller and project
        if (members[msg.sender] != IProofOfChange.MemberType.DAOMember) 
            revert IProofOfChange.UnauthorizedDAO();
        
        Project storage project = projects[projectId];
        if (project.proposer == address(0)) revert IProofOfChange.ProjectNotFound();
        
        // Validate status transitions
        if (newStatus == ProjectStatus.Archived) {
            if (project.status != ProjectStatus.Completed) 
                revert IProofOfChange.InvalidStatusTransition();
        } else if (newStatus == ProjectStatus.Completed) {
            if (project.currentPhase != IProofOfChange.VoteType.Completion || 
                !_isApproved(project.attestationUIDs[IProofOfChange.VoteType.Completion])) 
                revert IProofOfChange.ProjectNotCompletable();
        }

        // Update status and emit event
        ProjectStatus oldStatus = project.status;
        project.status = newStatus;
        
        emit ProjectAction(
            projectId, 
            msg.sender, 
            ProjectActionType.StatusUpdated, 
            string(abi.encodePacked(
                "Status changed from ", 
                uint256(oldStatus).toString(), 
                " to ", 
                uint256(newStatus).toString()
            ))
        );
    }

    // SECTION 7: Voting and Attestation Functions

    /// @notice Creates a new attestation for a project phase
    /// @dev Only callable by project proposer for current phase
    /// @param projectId The ID of the project
    /// @param phase The phase to create attestation for
    /// @return attestationUID The unique identifier of the created attestation
    function createPhaseAttestation(
        bytes32 projectId,
        IProofOfChange.VoteType phase
    ) public 
        nonReentrant 
        whenNotPaused(IProofOfChange.FunctionGroup.ProjectManagement)
        notFrozen(projectId)
        returns (bytes32)
    {
        Project storage project = projects[projectId];
        if (project.proposer == address(0)) revert IProofOfChange.ProjectNotFound();
        if (msg.sender != project.proposer) revert IProofOfChange.UnauthorizedProposer();
        if (phase != project.currentPhase) revert IProofOfChange.InvalidPhase();

        // Create attestation data
        bytes memory attestationData = abi.encode(
            projectId,
            project.name,
            project.description,
            project.location,
            project.regionId,
            phase
        );

        // Create attestation using EAS
        bytes32 attestationUID = eas.attest(
            AttestationRequest({
                schema: LOCATION_SCHEMA,
                data: AttestationRequestData({
                    recipient: address(0),    // No specific recipient
                    expirationTime: 0,        // No expiration
                    revocable: true,
                    refUID: bytes32(0),       // No reference
                    data: attestationData,
                    value: 0                  // No value being sent
                })
            })
        );

        project.attestationUIDs[phase] = attestationUID;
        emit IProofOfChange.PhaseAttestationCreated(projectId, phase, attestationUID);

        // Initialize voting with default requirements
        this.initializeVoting(
            attestationUID,
            3,  // Required DAO votes
            3   // Required subDAO votes
        );

        return attestationUID;
    }

    /// @notice Casts a vote on a phase attestation
    /// @dev Only callable by DAO or subDAO members when voting is not paused
    /// @param attestationUID The attestation being voted on
    /// @param regionId The region ID for subDAO validation
    /// @param approve True to approve, false to reject
    function vote(
        bytes32 attestationUID, 
        uint256 regionId, 
        bool approve
    ) external nonReentrant whenNotPaused(IProofOfChange.FunctionGroup.Voting) {
        // Validate voter eligibility
        IProofOfChange.MemberType memberType = members[msg.sender];
        if (memberType == IProofOfChange.MemberType.NonMember) revert IProofOfChange.UnauthorizedDAO();
        
        Vote storage voteData = attestationVotes[attestationUID];
        if (voteData.hasVoted[msg.sender]) revert IProofOfChange.AlreadyVoted();
        
        // Verify attestation validity
        Attestation memory attestation = eas.getAttestation(attestationUID);
        if (attestation.schema != LOCATION_SCHEMA) revert IProofOfChange.InvalidAttestation();
        
        // Record vote
        voteData.hasVoted[msg.sender] = true;
        
        if (approve) {
            // Handle vote based on member type
            if (memberType == IProofOfChange.MemberType.SubDAOMember) {
                if (!regionSubDAOMembers[regionId][msg.sender]) revert IProofOfChange.SubDAOMemberNotFromRegion();
                voteData.subDaoVotesFor++;
            } else {
                voteData.daoVotesFor++;
            }
            
            // Check for approval threshold
            if (voteData.daoVotesFor >= voteData.daoVotesRequired && 
                voteData.subDaoVotesFor >= voteData.subDaoVotesRequired &&
                voteData.result == IProofOfChange.VoteResult.Pending) {
                voteData.result = IProofOfChange.VoteResult.Approved;
                emit IProofOfChange.AttestationApproved(attestationUID);
            }
        }
        
        emit IProofOfChange.VoteCast(attestationUID, msg.sender, memberType);
    }

    /// @notice Initializes voting parameters for an attestation
    /// @dev Only callable by DAO members for valid attestations
    function initializeVoting(
        bytes32 attestationUID, 
        uint256 daoVotesNeeded,
        uint256 subDaoVotesNeeded
    ) public whenNotPaused(IProofOfChange.FunctionGroup.Voting) {
        if (members[msg.sender] != IProofOfChange.MemberType.DAOMember) revert IProofOfChange.UnauthorizedDAO();
        
        Vote storage voteData = attestationVotes[attestationUID];
        if (voteData.daoVotesRequired != 0) revert IProofOfChange.InvalidVoteState();
        
        // Verify attestation validity
        Attestation memory attestation = eas.getAttestation(attestationUID);
        if (attestation.schema != LOCATION_SCHEMA) revert IProofOfChange.InvalidAttestation();
        
        // Set voting parameters
        voteData.daoVotesRequired = daoVotesNeeded;
        voteData.subDaoVotesRequired = subDaoVotesNeeded;
        voteData.votingEnds = block.timestamp + votingPeriod;
        emit IProofOfChange.VotingInitialized(attestationUID, voteData.votingEnds);
    }

    /// @notice Finalizes the voting process for an attestation
    /// @dev Can be called by anyone after voting period ends
    function finalizeVote(bytes32 attestationUID) external nonReentrant whenNotPaused(IProofOfChange.FunctionGroup.Voting) {
        Vote storage voteData = attestationVotes[attestationUID];
        if (voteData.votingEnds > block.timestamp) revert IProofOfChange.VotingPeriodNotEnded();
        if (voteData.isFinalized) revert IProofOfChange.VoteAlreadyFinalized();

        // Determine final result
        bool isApproved = voteData.daoVotesFor >= voteData.daoVotesRequired && 
                         voteData.subDaoVotesFor >= voteData.subDaoVotesRequired;
        
        voteData.result = isApproved ? IProofOfChange.VoteResult.Approved : IProofOfChange.VoteResult.Rejected;
        voteData.isFinalized = true;
        
        emit IProofOfChange.VoteFinalized(attestationUID, voteData.result);
    }

    /// @notice Checks if an attestation has been approved
    /// @dev Public view function wrapping internal check
    function getAttestationApprovalStatus(bytes32 attestationUID) external view returns (bool) {
        return _isApproved(attestationUID);
    }

    /// @notice Internal function to check attestation approval status
    function _isApproved(bytes32 attestationUID) internal view returns (bool) {
        return attestationVotes[attestationUID].result == IProofOfChange.VoteResult.Approved;
    }

    /// @notice Validates attestation data
    /// @dev Called by EAS system to verify attestation validity
    function isValid(
        address attester,
        bytes memory data
    ) external view returns (bool) {
        (
            bytes32 projectId,
            string memory name,
            string memory description,
            string memory location,
            uint256 regionId,
            IProofOfChange.VoteType phase
        ) = abi.decode(data, (bytes32, string, string, string, uint256, IProofOfChange.VoteType));

        Project storage project = projects[projectId];
        
        // Validate core requirements
        if (project.proposer == address(0) ||          // Project must exist
            attester != project.proposer ||            // Attester must be proposer
            phase != project.currentPhase ||           // Phase must match current
            regionId == 0 ||                           // Region must be valid
            bytes(name).length == 0 ||                 // Name must not be empty
            bytes(description).length == 0 ||          // Description must not be empty
            bytes(location).length == 0                // Location must not be empty
        ) {
            return false;
        }

        return true;
    }

    // SECTION 8: Fund Management

    /// @notice Releases funds for a specific project phase
    /// @dev Only callable when project is completed and phase is approved
    function releasePhaseFunds(
        bytes32 projectId, 
        IProofOfChange.VoteType phase
    ) external 
        nonReentrant 
        whenNotPaused(IProofOfChange.FunctionGroup.FundManagement)
        notFrozen(projectId)
    {
        Project storage project = projects[projectId];
        
        // Validation checks
        if (project.proposer == address(0)) revert IProofOfChange.ProjectNotFound();
        if (project.status != ProjectStatus.Completed) revert IProofOfChange.ProjectNotComplete();
        
        bytes32 attestationUID = project.attestationUIDs[phase];
        if (!_isApproved(attestationUID)) revert IProofOfChange.PhaseNotApproved();
        if (phaseFundsReleased[projectId][phase]) revert IProofOfChange.FundsAlreadyReleased();
        
        // Process fund release
        uint256 allocation = project.phaseAllocations[phase];
        phaseFundsReleased[projectId][phase] = true;
        
        (bool success, ) = project.proposer.call{value: allocation}("");
        if (!success) revert IProofOfChange.FundTransferFailed();
        
        emit PhaseFundsReleased(
            projectId,
            phase,
            project.proposer,
            allocation,
            block.timestamp
        );
    }

    /// @notice Validates that phase allocations sum to total funds
    /// @dev Internal helper function for fund validation
    function _validateFundAllocation(
        uint256[] memory phaseAllocations, 
        uint256 totalFunds
    ) internal pure returns (bool) {
        if (phaseAllocations.length != 3) return false;
        
        uint256 total = 0;
        for (uint256 i = 0; i < phaseAllocations.length; i++) {
            total += phaseAllocations[i];
        }
        
        return total == totalFunds;
    }

    /// @notice Gets the financial details of a project
    /// @dev Returns allocation and release status for all phases
    function getProjectFinancials(
        bytes32 projectId
    ) external view returns (
        uint256 totalRequested,
        uint256 initialPhaseAmount,
        uint256 progressPhaseAmount,
        uint256 completionPhaseAmount,
        bool[] memory phasesFunded
    ) {
        Project storage project = projects[projectId];
        bool[] memory funded = new bool[](3);
        
        // Get release status for each phase
        funded[0] = phaseFundsReleased[projectId][IProofOfChange.VoteType.Initial];
        funded[1] = phaseFundsReleased[projectId][IProofOfChange.VoteType.Progress];
        funded[2] = phaseFundsReleased[projectId][IProofOfChange.VoteType.Completion];
        
        return (
            project.requestedFunds,
            project.phaseAllocations[IProofOfChange.VoteType.Initial],
            project.phaseAllocations[IProofOfChange.VoteType.Progress],
            project.phaseAllocations[IProofOfChange.VoteType.Completion],
            funded
        );
    }

    /// @notice Updates the weights for each project phase
    /// @dev Only callable by DAO members with voting
    function proposePhaseWeights(
        uint256 newInitialWeight,
        uint256 newProgressWeight,
        uint256 newCompletionWeight
    ) external 
        nonReentrant 
        whenNotPaused(IProofOfChange.FunctionGroup.ProjectManagement)
        onlyDAOMember 
    {
        // Validate total equals 100%
        if (newInitialWeight + newProgressWeight + newCompletionWeight != 100) {
            revert InvalidWeightTotal();
        }

        bytes32 proposalId = keccak256(abi.encodePacked(
            "phaseWeights",
            newInitialWeight,
            newProgressWeight,
            newCompletionWeight,
            block.timestamp
        ));

        WeightProposal storage proposal = weightProposals[proposalId];
        proposal.initialWeight = newInitialWeight;
        proposal.progressWeight = newProgressWeight;
        proposal.completionWeight = newCompletionWeight;
        proposal.proposedAt = block.timestamp;
        proposal.votesRequired = minimumPauseVotes; // Reuse existing threshold or set new one
        proposal.exists = true;

        emit PhaseWeightsProposed(
            proposalId,
            newInitialWeight,
            newProgressWeight,
            newCompletionWeight,
            msg.sender
        );
    }

    /// @notice Vote on proposed phase weights
    /// @dev Only callable by DAO members
    function voteOnPhaseWeights(bytes32 proposalId, bool approve) external 
        nonReentrant 
        onlyDAOMember 
    {
        WeightProposal storage proposal = weightProposals[proposalId];
        if (!proposal.exists) revert ProposalNotFound();
        if (proposal.executed) revert ProposalAlreadyExecuted();
        if (proposal.hasVoted[msg.sender]) revert AlreadyVoted();

        proposal.hasVoted[msg.sender] = true;

        if (approve) {
            proposal.votesReceived++;
            
            // If threshold met, update weights
            if (proposal.votesReceived >= proposal.votesRequired) {
                phaseWeights.initialWeight = proposal.initialWeight;
                phaseWeights.progressWeight = proposal.progressWeight;
                phaseWeights.completionWeight = proposal.completionWeight;
                phaseWeights.lastUpdated = block.timestamp;
                
                proposal.executed = true;

                emit PhaseWeightsUpdated(
                    proposalId,
                    proposal.initialWeight,
                    proposal.progressWeight,
                    proposal.completionWeight
                );
            }
        }

        emit WeightVoteCast(proposalId, msg.sender, approve);
    }

    /// @notice Modified calculation function to use current weights
    function calculateOverallCompletion(bytes32 projectId) public view returns (uint256) {
        ProjectProgress storage progress = projectProgress[projectId];
        
        uint256 overallCompletion = 
            (progress.phaseCompletionPercentages[IProofOfChange.VoteType.Initial] * phaseWeights.initialWeight +
            progress.phaseCompletionPercentages[IProofOfChange.VoteType.Progress] * phaseWeights.progressWeight +
            progress.phaseCompletionPercentages[IProofOfChange.VoteType.Completion] * phaseWeights.completionWeight) / 100;
            
        return overallCompletion;
    }

    /// @notice Gets the current phase weights
    function getCurrentPhaseWeights(bytes32 projectId) external view override returns (
        uint256 initialWeight,
        uint256 progressWeight,
        uint256 completionWeight
    ) {
        return (
            phaseWeights.initialWeight,
            phaseWeights.progressWeight,
            phaseWeights.completionWeight
        );
    }

    // SECTION 9: Media and Milestone Management

    /// @notice Adds media data for a specific project phase
    /// @dev Can only be called once per phase by the project proposer
    function addPhaseMedia(
        bytes32 projectId,
        IProofOfChange.VoteType phase,
        string[] calldata mediaTypes,
        string[] calldata mediaData,
        string calldata mediaDescription
    ) external 
        nonReentrant 
        whenNotPaused(IProofOfChange.FunctionGroup.ProjectManagement)
        notFrozen(projectId)
    {
        Project storage project = projects[projectId];
        if (project.proposer == address(0)) revert IProofOfChange.ProjectNotFound();
        if (msg.sender != project.proposer) revert IProofOfChange.UnauthorizedProposer();
        if (phase != project.currentPhase) revert IProofOfChange.InvalidPhase();
        if (mediaTypes.length == 0 || mediaTypes.length != mediaData.length) revert IProofOfChange.InvalidMediaData();
        if (project.media[phase].mediaTypes.length > 0) revert IProofOfChange.MediaAlreadyExists();

        project.media[phase] = Media({
            mediaTypes: mediaTypes,
            mediaData: mediaData,
            timestamp: block.timestamp,
            description: mediaDescription,
            verified: false
        });

        emit MediaAction(
            projectId,
            phase,
            mediaTypes,
            mediaData,
            block.timestamp,
            MediaActionType.Added
        );
    }

    /// @notice Updates the completion status of a project milestone
    /// @dev Only callable by project proposer for existing milestones
    function updateMilestone(
        bytes32 projectId,
        string calldata milestone,
        bool completed
    ) external 
        nonReentrant 
        whenNotPaused(IProofOfChange.FunctionGroup.ProjectManagement)
        notFrozen(projectId)
    {
        Project storage project = projects[projectId];
        if (project.proposer != msg.sender) revert IProofOfChange.UnauthorizedProposer();
        
        PhaseProgress storage progress = project.phaseProgress[project.currentPhase];
        bool milestoneExists = false;
        
        for (uint i = 0; i < progress.milestones.length; i++) {
            if (keccak256(bytes(progress.milestones[i])) == keccak256(bytes(milestone))) {
                milestoneExists = true;
                break;
            }
        }
        
        if (!milestoneExists) revert IProofOfChange.InvalidMilestone();
        
        progress.completedMilestones[milestone] = completed;
        
        emit MilestoneUpdated(projectId, project.currentPhase, milestone, completed);
    }

    /// @notice Adds initial media to a project
    /// @dev Called during project creation
    function _addInitialMedia(
        bytes32 projectId,
        string[] memory mediaTypes,
        string[] memory mediaData,
        string memory mediaDescription
    ) internal {
        Project storage project = projects[projectId];
        project.media[IProofOfChange.VoteType.Initial] = Media({
            mediaTypes: mediaTypes,
            mediaData: mediaData,
            timestamp: block.timestamp,
            description: mediaDescription,
            verified: false
        });
        project.hasInitialMedia = true;
    }

    /// @notice Initializes phase progress tracking
    /// @dev Sets up milestones and timing for a project phase
    function _initializePhaseProgress(
        bytes32 projectId,
        IProofOfChange.VoteType phase,
        uint256 duration,
        bool requiresMedia,
        string[] memory milestones
    ) internal {
        Project storage project = projects[projectId];
        PhaseProgress storage progress = project.phaseProgress[phase];
        
        progress.startTime = block.timestamp;
        progress.targetEndTime = block.timestamp + duration;
        progress.requiresMedia = requiresMedia;
        progress.isComplete = false;
        
        for (uint256 i = 0; i < milestones.length; i++) {
            progress.milestones.push(milestones[i]);
            progress.completedMilestones[milestones[i]] = false;
        }
    }

    // SECTION 10: Emergency and Administrative Functions

    /// @notice Emergency function to freeze project operations
    /// @dev Requires emergency admin consensus
    function emergencyProjectAction(
        bytes32 projectId,
        uint256 freezeDuration
    ) external 
        nonReentrant 
        requiresEmergencyConsensus(
            keccak256(abi.encodePacked("emergencyFreeze", projectId))
        ) 
    {
        if (freezeDuration > 30 days) revert IProofOfChange.InvalidFreezeDuration();
        projectFrozenUntil[projectId] = block.timestamp + freezeDuration;
        emit ProjectFrozen(projectId, projectFrozenUntil[projectId]);
    }

    /// @notice Internal function to unpause a function group
    /// @dev Called automatically when pause duration expires
    function _unpause(IProofOfChange.FunctionGroup group) internal {
        PauseConfig storage config = pauseConfigs[group];
        config.isPaused = false;
        config.pauseEnds = 0;
        emit FunctionGroupUnpaused(group);
    }

    /// @notice Checks if an address is an emergency admin
    /// @return bool True if address is an emergency admin
    function isEmergencyAdmin(address account) public view returns (bool) {
        for (uint256 i = 0; i < emergencyAdmins.length; i++) {
            if (emergencyAdmins[i] == account) {
                return true;
            }
        }
        return false;
    }

    /// @notice Updates the voting period duration
    /// @dev Only callable by DAO members
    /// @param newPeriodInDays New voting period duration in days
    function updateVotingPeriod(
        uint256 newPeriodInDays
    ) external 
        onlyDAOMember 
        whenNotPaused(FunctionGroup.ProjectManagement)
    {
        // Validate new period (minimum 1 day, maximum 30 days)
        if (newPeriodInDays < 1 || newPeriodInDays > 30) {
            revert InvalidVotingPeriod();
        }
        
        uint256 oldPeriod = votingPeriod;
        votingPeriod = newPeriodInDays * 1 days;
        
        emit VotingPeriodUpdated(oldPeriod, votingPeriod);
    }

    // SECTION 11: View Functions

    /// @notice Gets detailed project information
    /// @param projectId The ID of the project to query
    function getProjectDetails(
        bytes32 projectId
    ) external view returns (
        address proposer,
        string memory name,
        string memory description,
        string memory location,
        uint256 regionId,
        IProofOfChange.VoteType currentPhase,
        ProjectStatus status,
        uint256 startDate,
        uint256 expectedDuration
    ) {
        Project storage project = projects[projectId];
        return (
            project.proposer,
            project.name,
            project.description,
            project.location,
            project.regionId,
            project.currentPhase,
            project.status,
            project.startDate,
            project.expectedDuration
        );
    }

    /// @notice Gets phase progress information
    /// @param projectId The ID of the project
    /// @param phase The phase to query
    function getPhaseProgress(
        bytes32 projectId, 
        IProofOfChange.VoteType phase
    ) external view returns (
        uint256 startTime,
        uint256 targetEndTime,
        bool requiresMedia,
        bool isComplete,
        string[] memory milestones,
        bool[] memory completedStatus
    ) {
        Project storage project = projects[projectId];
        PhaseProgress storage progress = project.phaseProgress[phase];
        
        bool[] memory completed = new bool[](progress.milestones.length);
        for (uint256 i = 0; i < progress.milestones.length; i++) {
            completed[i] = progress.completedMilestones[progress.milestones[i]];
        }
        
        return (
            progress.startTime,
            progress.targetEndTime,
            progress.requiresMedia,
            progress.isComplete,
            progress.milestones,
            completed
        );
    }

    function addDAOMember(address member) external onlyDAOMember {
        members[member] = MemberType.DAOMember;
        emit MemberAction(member, MemberType.DAOMember, MemberType.NonMember, 0, false);
    }

    function addSubDAOMember(address member, uint256 regionId) external onlyDAOMember {
        regionSubDAOMembers[regionId][member] = true;
        members[member] = MemberType.SubDAOMember;
        emit MemberAction(member, MemberType.SubDAOMember, MemberType.NonMember, regionId, false);
    }

    function removeDAOMember(address member) external onlyDAOMember {
        MemberType previousType = members[member];
        delete members[member];
        emit MemberAction(member, MemberType.NonMember, previousType, 0, true);
    }

    function updateMember(
        address member, 
        MemberType newType, 
        uint256 regionId
    ) external onlyDAOMember {
        MemberType previousType = members[member];
        members[member] = newType;
        if (newType == MemberType.SubDAOMember) {
            regionSubDAOMembers[regionId][member] = true;
        }
        emit MemberAction(member, newType, previousType, regionId, false);
    }

    function proposePause(
        FunctionGroup group, 
        uint256 duration
    ) external onlyDAOMember returns (bytes32) {
        if (duration > STANDARD_PAUSE_DURATION) revert InvalidPauseDuration();
        
        bytes32 proposalId = keccak256(abi.encodePacked(group, duration, block.timestamp));
        PauseVoting storage voting = pauseVotes[proposalId];
        
        voting.votesRequired = minimumPauseVotes;
        voting.duration = duration;
        voting.proposedAt = block.timestamp;
        
        emit PauseProposed(group, duration, proposalId);
        return proposalId;
    }

    function castPauseVote(bytes32 proposalId) external onlyDAOMember {
        PauseVoting storage voting = pauseVotes[proposalId];
        if (voting.proposedAt == 0) revert PauseProposalNotFound();
        if (voting.hasVoted[msg.sender]) revert AlreadyVotedForPause();
        
        voting.hasVoted[msg.sender] = true;
        voting.votesReceived++;
        
        emit PauseVoteCast(proposalId, msg.sender);
    }

    function emergencyPause(FunctionGroup group) external {
        if (!isEmergencyAdmin(msg.sender)) revert UnauthorizedEmergencyAdmin();
        
        PauseConfig storage config = pauseConfigs[group];
        config.isPaused = true;
        config.pauseEnds = block.timestamp + EMERGENCY_PAUSE_DURATION;
        
        emit FunctionGroupPaused(group, config.pauseEnds);
    }

    function getUserProjects(address user) external view returns (bytes32[] memory) {
        return userProjects[user];
    }

    function getProjectStatus(bytes32 projectId) external view returns (ProjectStatus) {
        return projects[projectId].status;
    }

    function isProjectDelayed(bytes32 projectId) external view returns (bool) {
        Project storage project = projects[projectId];
        PhaseProgress storage progress = project.phaseProgress[project.currentPhase];
        return block.timestamp > progress.targetEndTime;
    }

    // Implement SchemaResolver abstract functions
    
    /// @notice Hook called by EAS during attestation creation
    /// @dev Validates attestation requirements and project state before allowing attestation
    /// @param attestation The attestation data being created
    /// @param value The value being sent with the attestation (unused)
    /// @return bool True if attestation is valid and should be allowed, false otherwise
    function onAttest(
        Attestation calldata attestation, 
        uint256 value
    ) internal virtual override returns (bool) {
        // Decode the attestation data
        (
            bytes32 projectId,
            string memory name,
            string memory description,
            string memory location,
            uint256 regionId,
            IProofOfChange.VoteType phase
        ) = abi.decode(attestation.data, (bytes32, string, string, string, uint256, IProofOfChange.VoteType));

        Project storage project = projects[projectId];

        // Validation checks
        if (project.proposer == address(0)) return false;  // Project must exist
        if (attestation.attester != project.proposer) return false;  // Only proposer can attest
        if (phase != project.currentPhase) return false;  // Phase must match current
        
        // Check if required media is present for this phase
        if (project.phaseProgress[phase].requiresMedia && 
            project.media[phase].mediaTypes.length == 0) {
            return false;  // Media required but not provided
        }

        // Check if all milestones are completed
        PhaseProgress storage progress = project.phaseProgress[phase];
        for (uint i = 0; i < progress.milestones.length; i++) {
            if (!progress.completedMilestones[progress.milestones[i]]) {
                return false;  // Not all milestones completed
            }
        }

        emit AttestationValidated(projectId, phase, true);
        return true;
    }

    /// @notice Hook called by EAS during attestation revocation
    /// @dev Validates revocation permissions and handles cleanup of associated data
    /// @param attestation The attestation data being revoked
    /// @param value The value being sent with the revocation (unused)
    /// @return bool True if revocation is allowed, false otherwise
    function onRevoke(
        Attestation calldata attestation, 
        uint256 value
    ) internal virtual override returns (bool) {
        // Decode the attestation data
        (bytes32 projectId,,,,, IProofOfChange.VoteType phase) = 
            abi.decode(attestation.data, (bytes32, string, string, string, uint256, IProofOfChange.VoteType));

        // Only allow revocation if:
        // 1. Called by a DAO member
        // 2. Project is not completed
        // 3. No funds have been released for this phase
        if (members[msg.sender] != IProofOfChange.MemberType.DAOMember) return false;
        if (projects[projectId].status == ProjectStatus.Completed) return false;
        if (phaseFundsReleased[projectId][phase]) return false;

        // Reset phase progress and voting data
        delete attestationVotes[attestation.uid];
        projects[projectId].phaseProgress[phase].isComplete = false;

        emit AttestationRevoked(
            projectId,
            phase,
            msg.sender,
            block.timestamp
        );
        return true;
    }

    /// @notice Emitted when an attestation is validated
    /// @param projectId The ID of the project being attested
    /// @param phase The project phase being attested
    /// @param success Whether the attestation validation passed
    event AttestationValidated(
        bytes32 indexed projectId,
        IProofOfChange.VoteType phase,
        bool success
    );

    /// @notice Emitted when an attestation is revoked
    /// @param projectId The ID of the project whose attestation was revoked
    /// @param phase The project phase that was revoked
    /// @param revoker The address that performed the revocation
    /// @param timestamp The time when the revocation occurred
    event AttestationRevoked(
        bytes32 indexed projectId,
        IProofOfChange.VoteType phase,
        address revoker,
        uint256 timestamp
    );


}
