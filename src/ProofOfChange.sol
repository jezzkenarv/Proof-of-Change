// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IEAS, Attestation, AttestationRequest, AttestationRequestData} from "@eas/IEAS.sol";
import {SchemaResolver} from "@eas/resolver/SchemaResolver.sol";
import {IProofOfChange} from "./Interfaces/IProofOfChange.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title Proof of Change
 * @notice A decentralized protocol for managing project attestations and milestone-based funding
 * @dev Implements EAS schema resolver for attestations and includes reentrancy protection
 */
contract ProofOfChange is SchemaResolver, IProofOfChange, ReentrancyGuard {
    using Strings for uint256;

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS & IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Schema ID for project logbook attestations
    bytes32 public constant LOGBOOK_SCHEMA = 0xb16fa048b0d597f5a821747eba64efa4762ee5143e9a80600d0005386edfc995;
    
    /// @notice Duration of emergency pause (3 days)
    uint256 public constant EMERGENCY_PAUSE_DURATION = 3 days;
    
    /// @notice Duration of standard pause (14 days)
    uint256 public constant STANDARD_PAUSE_DURATION = 14 days;
    
    /// @notice Required waiting period for timelocked operations
    uint256 public constant TIMELOCK_PERIOD = 24 hours;
    
    /// @notice Minimum number of emergency admins required for emergency actions
    uint256 public constant EMERGENCY_THRESHOLD = 2;

    /// @notice Reference to the Ethereum Attestation Service contract
    IEAS private immutable eas;
    
    /// @notice Minimum votes required to pause contract functions
    uint256 public immutable minimumPauseVotes;

    /*//////////////////////////////////////////////////////////////
                            DATA STRUCTURES
    //////////////////////////////////////////////////////////////*/

    struct PauseVoting {
        uint256 votesRequired;
        uint256 votesReceived;
        uint256 duration;
        uint256 proposedAt;
        bool executed;
        mapping(address => bool) hasVoted;
    }

    struct PauseConfig {
        bool isPaused;
        uint256 pauseEnds;
        bool requiresVoting;
    }

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

    struct ProjectProgress {
        uint256 completionPercentage;
        uint256 totalFundsReleased;
        mapping(IProofOfChange.VoteType => uint256) phaseCompletionPercentages;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Mapping of attestation UIDs to their vote data
    mapping(bytes32 => Vote) public attestationVotes;

    /// @notice Mapping of addresses to their member type
    mapping(address => IProofOfChange.MemberType) public members;

    /// @notice Mapping of region IDs to their subDAO members
    /// @dev regionId => member address => is member
    mapping(uint256 => mapping(address => bool)) public regionSubDAOMembers;

    /// @notice Mapping of project IDs to their data
    mapping(bytes32 => Project) public projects;

    /// @notice Mapping of user addresses to their project IDs
    mapping(address => bytes32[]) public userProjects;

    /// @notice Configuration for function group pauses
    mapping(IProofOfChange.FunctionGroup => PauseConfig) public pauseConfigs;

    /// @notice Active pause votes by proposal ID
    mapping(bytes32 => PauseVoting) public pauseVotes;

    /// @notice Duration of the voting period in seconds
    uint256 public votingPeriod;

    /// @notice Mapping of project IDs to their freeze end time
    mapping(bytes32 => uint256) public projectFrozenUntil;

    /// @notice Mapping of operation IDs to their timelock expiry
    mapping(bytes32 => uint256) public pendingOperations;

    /// @notice Tracks emergency approvals for operations
    /// @dev operationId => admin => has approved
    mapping(bytes32 => mapping(address => bool)) public emergencyApprovals;

    /// @notice List of addresses with emergency admin privileges
    address[] public emergencyAdmins;

    /// @notice Tracks which phases have had funds released
    /// @dev projectId => phase => funds released
    mapping(bytes32 => mapping(VoteType => bool)) public phaseFundsReleased;

    /// @notice Current weights for different project phases
    PhaseWeights public phaseWeights;

    /// @notice Active proposals to change phase weights
    mapping(bytes32 => WeightProposal) public weightProposals;

    /// @notice Tracks progress metrics for each project
    mapping(bytes32 => ProjectProgress) public projectProgress;

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Ensures the specified function group is not paused
    /// @param group The function group to check
    /// @dev Automatically lifts pause if duration has expired
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

    /// @notice Enforces timelock delay for sensitive operations
    /// @param operationId Unique identifier for the operation
    /// @dev Queues operation if not already queued, reverts if timelock not expired
    modifier timeLocked(bytes32 operationId) {
        if (pendingOperations[operationId] == 0) {
            pendingOperations[operationId] = block.timestamp + TIMELOCK_PERIOD;
            emit OperationQueued(operationId);
            revert IProofOfChange.OperationTimelocked(operationId);
        }

        if (block.timestamp < pendingOperations[operationId]) {
            revert IProofOfChange.TimelockNotExpired(
                operationId,
                pendingOperations[operationId]
            );
        }

        delete pendingOperations[operationId];
        _;
    }

    /// @notice Requires consensus from emergency admins
    /// @param operationId Unique identifier for the emergency operation
    /// @dev Tracks approvals and enforces minimum threshold
    modifier requiresEmergencyConsensus(bytes32 operationId) {
        if (!isEmergencyAdmin(msg.sender)) {
            revert IProofOfChange.UnauthorizedEmergencyAdmin();
        }

        emergencyApprovals[operationId][msg.sender] = true;
        
        uint256 approvalCount = 0;
        for (uint256 i = 0; i < emergencyAdmins.length; i++) {
            if (emergencyApprovals[operationId][emergencyAdmins[i]]) {
                approvalCount++;
            }
        }
        
        if (approvalCount < EMERGENCY_THRESHOLD) {
            revert IProofOfChange.InsufficientEmergencyApprovals(
                approvalCount,
                EMERGENCY_THRESHOLD
            );
        }
        _;
    }

    /// @notice Restricts access to DAO members only
    modifier onlyDAOMember() {
        if (members[msg.sender] != IProofOfChange.MemberType.DAOMember) {
            revert IProofOfChange.UnauthorizedDAO();
        }
        _;
    }

    /// @notice Restricts access to subDAO members of a specific region
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
    /// @param projectId The project ID to check
    modifier notFrozen(bytes32 projectId) {
        if (block.timestamp < projectFrozenUntil[projectId]) {
            revert ProjectNotActive();
        }
        _;
    }

    /// @notice Restricts access to project proposer
    /// @param projectId The project ID to check ownership for
    modifier onlyProposer(bytes32 projectId) {
        Project storage project = projects[projectId];
        if (project.proposer != msg.sender) {
            revert UnauthorizedProposer();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            PROJECT LIFECYCLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new project with the given parameters
    /// @param data The project creation data struct
    /// @return projectId The unique identifier of the created project
    /// @dev Requires funds to be sent equal to requestedFunds
    function createProject(ProjectCreationData calldata data) external payable nonReentrant returns (bytes32) {
        // Verify Logbook attestation
        Attestation memory attestation = eas.getAttestation(data.logbookAttestationUID);
        require(attestation.schema == LOGBOOK_SCHEMA, "Invalid attestation");

        // Validate parameters
        require(data.duration >= 1 days && data.duration <= 365 days, "Invalid duration");
        require(msg.value == data.requestedFunds, "Incorrect funds sent");

        bytes32 projectId = keccak256(
            abi.encodePacked(
                msg.sender,
                data.logbookAttestationUID,
                block.timestamp
            )
        );

        Project storage project = projects[projectId];
        project.proposer = msg.sender;
        project.name = data.name;
        project.description = data.description;
        project.requestedFunds = data.requestedFunds;
        project.expectedDuration = data.duration;
        project.createdAt = uint64(block.timestamp);
        project.startDate = uint64(data.startDate);
        project.status = ProjectStatus.Active;
        project.currentPhase = VoteType.Initial;
        project.regionId = data.regionId;
        
        // Store proof of content
        project.stateProofs[VoteType.Initial] = StateProof({
            attestationUID: data.logbookAttestationUID,
            contentHash: keccak256(bytes(data.contentCID)),
            timestamp: uint64(block.timestamp),
            verified: false
        });

        userProjects[msg.sender].push(projectId);

        emit ProjectCreated(
            projectId,
            msg.sender,
            data.name,
            data.regionId,
            data.requestedFunds,
            block.timestamp
        );

        return projectId;
    }

    /// @notice Advances a project to its next phase
    /// @param projectId The ID of the project to advance
    /// @dev Only callable by project proposer after current phase is approved
    function advanceToNextPhase(bytes32 projectId) external {
        Project storage project = projects[projectId];
        if (project.proposer == address(0)) revert IProofOfChange.ProjectNotFound();
        if (msg.sender != project.proposer) revert IProofOfChange.UnauthorizedProposer();

        // Verify current phase completion
        StateProof storage currentProof = project.stateProofs[project.currentPhase];
        Vote storage currentVote = attestationVotes[currentProof.attestationUID];
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
    /// @param projectId The ID of the project to update
    /// @param newStatus The new status to set
    /// @dev Only callable by DAO members
    function updateProjectStatus(bytes32 projectId, ProjectStatus newStatus) external {
        if (members[msg.sender] != IProofOfChange.MemberType.DAOMember) 
            revert IProofOfChange.UnauthorizedDAO();
        
        Project storage project = projects[projectId];
        if (project.proposer == address(0)) revert IProofOfChange.ProjectNotFound();
        
        // Validate status transitions
        if (newStatus == ProjectStatus.Completed) {
            StateProof storage proof = project.stateProofs[IProofOfChange.VoteType.Completion];
            if (project.currentPhase != IProofOfChange.VoteType.Completion || 
                !_isApproved(proof.attestationUID)) 
                revert IProofOfChange.ProjectNotCompletable();
        }

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

    /*//////////////////////////////////////////////////////////////
                            PROGRESS TRACKING
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates a milestone's completion status
    /// @param projectId The ID of the project
    /// @param milestone The milestone identifier
    /// @param completed Whether the milestone is completed
    /// @dev Only callable by project proposer
    function updateMilestone(bytes32 projectId, string calldata milestone, bool completed) external {
        Project storage project = projects[projectId];
        if (project.proposer != msg.sender) revert UnauthorizedProposer();
        
        PhaseProgress storage progress = project.phaseProgress[project.currentPhase];
        bool milestoneExists = false;
        
        for (uint i = 0; i < progress.milestones.length; i++) {
            if (keccak256(bytes(progress.milestones[i])) == keccak256(bytes(milestone))) {
                milestoneExists = true;
                break;
            }
        }
        
        if (!milestoneExists) revert InvalidMilestone();
        
        progress.completedMilestones[milestone] = completed;
        
        emit MilestoneUpdated(projectId, project.currentPhase, milestone, completed);
    }

    /// @notice Submits progress update for a project phase
    /// @param projectId The ID of the project
    /// @param logbookAttestationUID The attestation UID for the progress update
    /// @param contentCID The IPFS CID of the progress content
    /// @dev Creates new state proof for current phase
    function submitProgress(bytes32 projectId, bytes32 logbookAttestationUID, string calldata contentCID) external {
        Project storage project = projects[projectId];
        require(project.status == ProjectStatus.Active, "Project not active");

        VoteType currentPhase = project.currentPhase;
        
        project.stateProofs[currentPhase] = StateProof({
            attestationUID: logbookAttestationUID,
            contentHash: keccak256(bytes(contentCID)),
            timestamp: uint64(block.timestamp),
            verified: false
        });

        emit ProgressSubmitted(
            projectId,
            logbookAttestationUID,
            keccak256(bytes(contentCID))
        );
    }

    function _initializePhaseProgress(bytes32 projectId, VoteType phase, string[] memory milestones) internal {
        Project storage project = projects[projectId];
        PhaseProgress storage progress = project.phaseProgress[phase];
        
        progress.startTime = uint64(block.timestamp);
        progress.targetEndTime = uint64(block.timestamp + project.expectedDuration);
        progress.isComplete = false;
        
        for (uint256 i = 0; i < milestones.length; i++) {
            progress.milestones.push(milestones[i]);
            progress.completedMilestones[milestones[i]] = false;
        }
    }

    function _areMilestonesComplete(bytes32 projectId, VoteType phase) internal view returns (bool) {
        Project storage project = projects[projectId];
        PhaseProgress storage progress = project.phaseProgress[phase];
        
        for (uint256 i = 0; i < progress.milestones.length; i++) {
            if (!progress.completedMilestones[progress.milestones[i]]) {
                return false;
            }
        }
        return true;
    }

    function calculateOverallCompletion(bytes32 projectId) public view returns (uint256) {
        ProjectProgress storage progress = projectProgress[projectId];
        
        uint256 overallCompletion = 
            (progress.phaseCompletionPercentages[IProofOfChange.VoteType.Initial] * phaseWeights.initialWeight +
            progress.phaseCompletionPercentages[IProofOfChange.VoteType.Progress] * phaseWeights.progressWeight +
            progress.phaseCompletionPercentages[IProofOfChange.VoteType.Completion] * phaseWeights.completionWeight) / 100;
            
        return overallCompletion;
    }

    /*//////////////////////////////////////////////////////////////
                            VOTING SYSTEM
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new attestation for a project phase
    /// @param projectId The ID of the project
    /// @param phase The phase to create attestation for
    /// @return attestationUID The unique identifier of the created attestation
    /// @dev Only callable by project proposer for current phase
    function createPhaseAttestation(bytes32 projectId, IProofOfChange.VoteType phase) public returns (bytes32) {
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
                schema: LOGBOOK_SCHEMA,
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

        // Store in stateProofs instead of attestationUIDs
        project.stateProofs[phase] = StateProof({
            attestationUID: attestationUID,
            contentHash: bytes32(0), // This will be set later with submitProgress
            timestamp: uint64(block.timestamp),
            verified: false
        });

        emit IProofOfChange.PhaseAttestationCreated(projectId, phase, attestationUID);

        // Initialize voting with default requirements
        this.initializeVoting(
            attestationUID,
            3,  // Required DAO votes
            3   // Required subDAO votes
        );

        return attestationUID;
    }

    /// @notice Cast a vote on an attestation
    /// @param attestationUID The attestation to vote on
    /// @param regionId The region ID for subDAO validation
    /// @param approve True to vote in favor, false against
    function vote(bytes32 attestationUID, uint256 regionId, bool approve) external {
        // Validate voter eligibility
        IProofOfChange.MemberType memberType = members[msg.sender];
        if (memberType == IProofOfChange.MemberType.NonMember) revert IProofOfChange.UnauthorizedDAO();
        
        Vote storage voteData = attestationVotes[attestationUID];
        if (voteData.hasVoted[msg.sender]) revert IProofOfChange.AlreadyVoted();
        
        // Verify attestation validity
        Attestation memory attestation = eas.getAttestation(attestationUID);
        if (attestation.schema != LOGBOOK_SCHEMA) revert IProofOfChange.InvalidAttestation();
        
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

    /// @notice Initialize voting parameters for an attestation
    /// @param attestationUID The attestation to initialize voting for
    /// @param daoVotesNeeded Number of DAO votes required
    /// @param subDaoVotesNeeded Number of subDAO votes required
    /// @dev Only callable by DAO members
    function initializeVoting(bytes32 attestationUID, uint256 daoVotesNeeded, uint256 subDaoVotesNeeded) public {
        if (members[msg.sender] != IProofOfChange.MemberType.DAOMember) revert IProofOfChange.UnauthorizedDAO();
        
        Vote storage voteData = attestationVotes[attestationUID];
        if (voteData.daoVotesRequired != 0) revert IProofOfChange.InvalidVoteState();
        
        // Verify attestation validity
        Attestation memory attestation = eas.getAttestation(attestationUID);
        if (attestation.schema != LOGBOOK_SCHEMA) revert IProofOfChange.InvalidAttestation();
        
        // Set voting parameters with explicit type conversions
        voteData.daoVotesRequired = uint32(daoVotesNeeded);
        voteData.subDaoVotesRequired = uint32(subDaoVotesNeeded);
        voteData.votingEnds = uint64(block.timestamp + votingPeriod);
        
        emit IProofOfChange.VotingInitialized(attestationUID, voteData.votingEnds);
    }

    /// @notice Finalizes a vote after voting period ends
    /// @param attestationUID The attestation to finalize
    function finalizeVote(bytes32 attestationUID) external {
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

    /*//////////////////////////////////////////////////////////////
                            FUND MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Releases funds for a completed project phase
    /// @param projectId The ID of the project
    /// @param phase The phase to release funds for
    /// @dev Only callable after phase is approved and not already funded
    function releasePhaseFunds(bytes32 projectId, IProofOfChange.VoteType phase) external {
        Project storage project = projects[projectId];
        
        // Validation checks
        if (project.proposer == address(0)) revert IProofOfChange.ProjectNotFound();
        if (project.status != ProjectStatus.Completed) revert IProofOfChange.ProjectNotComplete();
        
        StateProof storage proof = project.stateProofs[phase];
        if (!_isApproved(proof.attestationUID)) revert IProofOfChange.PhaseNotApproved();
        if (phaseFundsReleased[projectId][phase]) revert IProofOfChange.FundsAlreadyReleased();
        
        // Calculate release amount using the getPhaseWeight function
        uint256 releaseAmount = (project.requestedFunds * getPhaseWeight(phase)) / 100;
        phaseFundsReleased[projectId][phase] = true;
        
        (bool success, ) = project.proposer.call{value: releaseAmount}("");
        if (!success) revert IProofOfChange.FundTransferFailed();
        
        emit PhaseFundsReleased(
            projectId,
            phase,
            project.proposer,
            releaseAmount,
            block.timestamp
        );
    }

    /// @notice Gets financial details for a project
    /// @param projectId The ID of the project
    /// @return Financial information including amounts and funding status
    function getProjectFinancials(bytes32 projectId) external view returns (
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
        
        // Calculate phase amounts based on weights
        uint256 totalFunds = project.requestedFunds;
        return (
            totalFunds,
            (totalFunds * getPhaseWeight(IProofOfChange.VoteType.Initial)) / 100,
            (totalFunds * getPhaseWeight(IProofOfChange.VoteType.Progress)) / 100,
            (totalFunds * getPhaseWeight(IProofOfChange.VoteType.Completion)) / 100,
            funded
        );
    }

    /// @notice Proposes new weights for project phases
    /// @param newInitialWeight Weight for initial phase (percentage)
    /// @param newProgressWeight Weight for progress phase (percentage)
    /// @param newCompletionWeight Weight for completion phase (percentage)
    /// @dev Total weights must equal 100
    function proposePhaseWeights(uint256 newInitialWeight, uint256 newProgressWeight, uint256 newCompletionWeight) external {
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

    /// @notice Vote on a proposed phase weight change
    /// @param proposalId The ID of the weight proposal
    /// @param approve True to vote in favor, false against
    function voteOnPhaseWeights(bytes32 proposalId, bool approve) external {
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

    /*//////////////////////////////////////////////////////////////
                            EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function emergencyProjectAction(bytes32 projectId, uint256 freezeDuration) external {
        if (freezeDuration > 30 days) revert IProofOfChange.InvalidFreezeDuration();
        projectFrozenUntil[projectId] = block.timestamp + freezeDuration;
        emit ProjectFrozen(projectId, projectFrozenUntil[projectId]);
    }

    function emergencyPause(FunctionGroup group) external {
        if (!isEmergencyAdmin(msg.sender)) revert UnauthorizedEmergencyAdmin();
        
        PauseConfig storage config = pauseConfigs[group];
        config.isPaused = true;
        config.pauseEnds = block.timestamp + EMERGENCY_PAUSE_DURATION;
        
        emit FunctionGroupPaused(group, config.pauseEnds);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMINISTRATIVE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Adds a new DAO member
    /// @param member Address of the new member
    /// @dev Only callable by existing DAO members
    function addDAOMember(address member) external onlyDAOMember {
        members[member] = MemberType.DAOMember;
        emit MemberAction(member, MemberType.DAOMember, MemberType.NonMember, 0, false);
    }

    /// @notice Adds a new subDAO member for a specific region
    /// @param member Address of the new member
    /// @param regionId ID of the region for the subDAO
    /// @dev Only callable by DAO members
    function addSubDAOMember(address member, uint256 regionId) external onlyDAOMember {
        regionSubDAOMembers[regionId][member] = true;
        members[member] = MemberType.SubDAOMember;
        emit MemberAction(member, MemberType.SubDAOMember, MemberType.NonMember, regionId, false);
    }

    /// @notice Removes a DAO member
    /// @param member Address of the member to remove
    /// @dev Only callable by DAO members
    function removeDAOMember(address member) external onlyDAOMember {
        MemberType previousType = members[member];
        delete members[member];
        emit MemberAction(member, MemberType.NonMember, previousType, 0, true);
    }

    /// @notice Updates a member's type and region
    /// @param member Address of the member to update
    /// @param newType New member type to assign
    /// @param regionId Region ID for subDAO members
    /// @dev Only callable by DAO members
    function updateMember(address member, MemberType newType, uint256 regionId) external onlyDAOMember {
        MemberType previousType = members[member];
        members[member] = newType;
        if (newType == MemberType.SubDAOMember) {
            regionSubDAOMembers[regionId][member] = true;
        }
        emit MemberAction(member, newType, previousType, regionId, false);
    }

    /// @notice Updates the voting period duration
    /// @param newPeriodInDays New voting period in days (1-30)
    function updateVotingPeriod(uint256 newPeriodInDays) external {
        if (newPeriodInDays < 1 || newPeriodInDays > 30) {
            revert InvalidVotingPeriod();
        }
        
        uint256 oldPeriod = votingPeriod;
        votingPeriod = newPeriodInDays * 1 days;
        
        emit VotingPeriodUpdated(oldPeriod, votingPeriod);
    }

    /// @notice Proposes a pause for a function group
    /// @param group The function group to pause
    /// @param duration Duration of the pause in seconds
    /// @return proposalId The ID of the created pause proposal
    function proposePause(FunctionGroup group, uint256 duration) external onlyDAOMember returns (bytes32) {
        if (duration > STANDARD_PAUSE_DURATION) revert InvalidPauseDuration();
        
        bytes32 proposalId = keccak256(abi.encodePacked(group, duration, block.timestamp));
        PauseVoting storage voting = pauseVotes[proposalId];
        
        voting.votesRequired = minimumPauseVotes;
        voting.duration = duration;
        voting.proposedAt = block.timestamp;
        
        emit PauseProposed(group, duration, proposalId);
        return proposalId;
    }

    /// @notice Casts a vote on a pause proposal
    /// @param proposalId The ID of the pause proposal
    /// @dev Only callable by DAO members
    function castPauseVote(bytes32 proposalId) external onlyDAOMember {
        PauseVoting storage voting = pauseVotes[proposalId];
        if (voting.proposedAt == 0) revert PauseProposalNotFound();
        if (voting.hasVoted[msg.sender]) revert AlreadyVotedForPause();
        
        voting.hasVoted[msg.sender] = true;
        voting.votesReceived++;
        
        emit PauseVoteCast(proposalId, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getProjectDetails(bytes32 projectId) external view returns (
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

    function getPhaseProgress(bytes32 projectId, VoteType phase) external view override returns (
        uint256 startTime,
        uint256 endTime,
        bool completed,
        bytes32 attestationUID,
        bytes32 contentHash
    ) {
        Project storage project = projects[projectId];
        StateProof storage proof = project.stateProofs[phase];
        
        return (
            proof.timestamp,
            proof.timestamp + project.expectedDuration,
            proof.verified,
            proof.attestationUID,
            proof.contentHash
        );
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

    function getStateProof(bytes32 projectId, VoteType phase) external view returns (
        bytes32 attestationUID,
        bytes32 contentHash,
        uint256 timestamp,
        bool verified
    ) {
        StateProof storage proof = projects[projectId].stateProofs[phase];
        return (
            proof.attestationUID,
            proof.contentHash,
            proof.timestamp,
            proof.verified
        );
    }

    /*//////////////////////////////////////////////////////////////
                            ATTESTATION HANDLERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Handles attestation validation
    /// @param attestation The attestation to validate
    /// @param value Any value sent with the attestation
    /// @return bool Whether the attestation is valid
    /// @dev Implements EAS schema resolver interface
    function onAttest(Attestation calldata attestation, uint256 value) internal virtual override returns (bool) {
        // Check if this is a Logbook attestation
        if (attestation.schema == LOGBOOK_SCHEMA) {
            // Decode Logbook data
            (
                uint256 logbookTimestamp,
                string memory logbookLocation,
                string memory logbookMemo
            ) = decodeLogbookData(attestation.data);

            // Store Logbook proof
            Project storage projectData = projects[attestation.refUID];
            projectData.stateProofs[projectData.currentPhase] = StateProof({
                attestationUID: attestation.uid,
                contentHash: keccak256(abi.encodePacked(logbookLocation, logbookMemo)),
                timestamp: uint64(logbookTimestamp),
                verified: false
            });

            return true;
        }

        // Decode project attestation data
        (
            bytes32 projectId,
            string memory name,
            string memory description,
            string memory location,
            uint256 regionId,
            IProofOfChange.VoteType phase
        ) = abi.decode(attestation.data, (
            bytes32,
            string,
            string,
            string,
            uint256,
            IProofOfChange.VoteType
        ));

        Project storage project = projects[projectId];

        // Validation checks
        if (project.proposer == address(0)) return false;  // Project must exist
        if (attestation.attester != project.proposer) return false;  // Only proposer can attest
        if (phase != project.currentPhase) return false;  // Phase must match current
        
        // Check if required milestones are complete
        if (!_areMilestonesComplete(projectId, phase)) {
            revert IProofOfChange.InvalidPhase();
        }

        emit AttestationValidated(projectId, phase, true);
        return true;
    }

    /// @notice Handles attestation revocation
    /// @param attestation The attestation to revoke
    /// @param value Any value sent with the revocation
    /// @return bool Whether the revocation is valid
    /// @dev Only allows revocation under specific conditions
    function onRevoke(Attestation calldata attestation, uint256 value) internal virtual override returns (bool) {
        // Decode the attestation data
        (bytes32 projectId,,,,, IProofOfChange.VoteType phase) = 
            abi.decode(attestation.data, (bytes32, string, string, string, uint256, IProofOfChange.VoteType));

        Project storage project = projects[projectId];

        // Only allow revocation if:
        // 1. Called by a DAO member
        // 2. Project is not completed
        // 3. No funds have been released for this phase
        if (members[msg.sender] != IProofOfChange.MemberType.DAOMember) return false;
        if (project.status == ProjectStatus.Completed) return false;
        if (phaseFundsReleased[projectId][phase]) return false;

        // Reset state proof and voting data
        delete attestationVotes[attestation.uid];
        delete project.stateProofs[phase];

        emit AttestationRevoked(
            projectId,
            phase,
            msg.sender,
            block.timestamp
        );
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Removes pause from a function group
    /// @param group The function group to unpause
    function _unpause(IProofOfChange.FunctionGroup group) internal {
        PauseConfig storage config = pauseConfigs[group];
        config.isPaused = false;
        config.pauseEnds = 0;
        emit FunctionGroupUnpaused(group);
    }

    /// @notice Checks if an address is an emergency admin
    /// @param account The address to check
    /// @return bool True if address is emergency admin
    function isEmergencyAdmin(address account) public view returns (bool) {
        for (uint256 i = 0; i < emergencyAdmins.length; i++) {
            if (emergencyAdmins[i] == account) {
                return true;
            }
        }
        return false;
    }

    /// @notice Gets the weight for a specific phase
    /// @param phase The phase to get weight for
    /// @return uint256 The weight percentage for the phase
    function getPhaseWeight(VoteType phase) internal view returns (uint256) {
        if (phase == VoteType.Initial) {
            return phaseWeights.initialWeight;
        } else if (phase == VoteType.Progress) {
            return phaseWeights.progressWeight;
        } else if (phase == VoteType.Completion) {
            return phaseWeights.completionWeight;
        }
        revert IProofOfChange.InvalidPhase();
    }

    /// @notice Decodes logbook attestation data
    /// @param data The encoded attestation data
    /// @return Decoded logbook fields
    function decodeLogbookData(bytes memory data) internal pure returns (
        uint256 timestamp,
        string memory location,
        string memory memo
    ) {
        (
            timestamp,
            ,   // eventType
            location,
            memo
        ) = abi.decode(
            data,
            (
                uint256,    // timestamp
                string,     // eventType
                string,     // location
                string     // memo
            )
        );
    }
}
