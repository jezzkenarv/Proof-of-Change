// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IEAS, Attestation, AttestationRequest, AttestationRequestData} from "@eas/IEAS.sol";
import {SchemaResolver} from "@eas/resolver/SchemaResolver.sol";
import {IProofOfChange} from "./Interfaces/IProofOfChange.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract ProofOfChange is SchemaResolver, IProofOfChange, ReentrancyGuard {
    using Strings for uint256;

    // Constants
    bytes32 public constant LOCATION_SCHEMA = 0xba4171c92572b1e4f241d044c32cdf083be9fd946b8766977558ca6378c824e2;
    
    // Structs
    struct Project {
        address proposer;
        IProofOfChange.VoteType currentPhase;
        ProjectStatus status;
        bool hasInitialMedia;
        uint256 regionId;
        string name;
        string description;
        string location;
        uint256 createdAt;
        uint256 expectedDuration;
        uint256 requestedFunds;
        uint256 startDate;
        bool fundsReleased;
        mapping(IProofOfChange.VoteType => Media) media;
        mapping(IProofOfChange.VoteType => bytes32) attestationUIDs;
        mapping(IProofOfChange.VoteType => PhaseProgress) phaseProgress;
        mapping(IProofOfChange.VoteType => uint256) phaseAllocations;
    }

    struct PauseVoting {
        uint256 votesRequired;
        uint256 votesReceived;
        uint256 duration;
        uint256 proposedAt;
        mapping(address => bool) hasVoted;
        bool executed;
    }

    struct PauseConfig {
        bool isPaused;
        uint256 pauseEnds;
        bool requiresVoting;
    }

    struct PhaseProgress {
        uint256 startTime;
        uint256 targetEndTime;
        bool requiresMedia;
        bool isComplete;
        string[] milestones;
        mapping(string => bool) completedMilestones;
    }

    // State variables
    mapping(bytes32 => Vote) public attestationVotes;
    mapping(address => IProofOfChange.MemberType) public members;
    mapping(uint256 => mapping(address => bool)) public regionSubDAOMembers;
    IEAS private immutable eas;
    mapping(bytes32 => Project) public projects;
    mapping(address => bytes32[]) public userProjects;
    mapping(IProofOfChange.FunctionGroup => PauseConfig) public pauseConfigs;
    mapping(bytes32 => PauseVoting) public pauseVotes;
    
    // Cool-down period duration
    uint256 public votingPeriod = 7 days;
    
    uint256 public constant EMERGENCY_PAUSE_DURATION = 3 days;
    uint256 public constant STANDARD_PAUSE_DURATION = 14 days;
    uint256 public immutable minimumPauseVotes;

    // Add frozen projects tracking
    mapping(bytes32 => uint256) public projectFrozenUntil;

    // Add new constants and state variables
    uint256 public constant TIMELOCK_PERIOD = 24 hours;
    uint256 public constant EMERGENCY_THRESHOLD = 2;
    
    mapping(bytes32 => uint256) public pendingOperations;
    mapping(bytes32 => mapping(address => bool)) public emergencyApprovals;
    address[] public emergencyAdmins;

    // Add new events
    event OperationQueued(bytes32 indexed operationId);
    event EmergencyAdminAdded(address indexed admin);
    event EmergencyAdminRemoved(address indexed admin);

    mapping(bytes32 => mapping(IProofOfChange.VoteType => bool)) public phaseFundsReleased;

    constructor(address easRegistry, address[] memory initialDAOMembers) SchemaResolver(IEAS(easRegistry)) {
        eas = IEAS(easRegistry);
        minimumPauseVotes = (initialDAOMembers.length * 2) / 3; // 66% of initial DAO members
        for (uint256 i = 0; i < initialDAOMembers.length; i++) {
            members[initialDAOMembers[i]] = IProofOfChange.MemberType.DAOMember;
            // Make initial DAO members emergency admins
            emergencyAdmins.push(initialDAOMembers[i]);
        }
    }

    // Modified modifier to check specific function group
    modifier whenNotPaused(IProofOfChange.FunctionGroup group) {
        PauseConfig storage config = pauseConfigs[group];
        if (config.isPaused) {
            if (config.pauseEnds != 0 && block.timestamp >= config.pauseEnds) {
                _unpause(group);
            } else {
                revert IProofOfChange.FunctionCurrentlyPaused(group, config.pauseEnds);
            }
        }
        _;
    }

    // New functions for pause management
    function proposePause(IProofOfChange.FunctionGroup group, uint256 duration) external override returns (bytes32) {
        if (members[msg.sender] != IProofOfChange.MemberType.DAOMember) revert IProofOfChange.UnauthorizedDAO();
        if (duration > STANDARD_PAUSE_DURATION) revert IProofOfChange.InvalidPauseDuration();

        bytes32 proposalId = keccak256(abi.encodePacked(group, duration, block.timestamp));
        PauseVoting storage voting = pauseVotes[proposalId];
        voting.votesRequired = minimumPauseVotes;
        voting.duration = duration;
        voting.proposedAt = block.timestamp;

        emit IProofOfChange.PauseProposed(group, duration, proposalId);
        
        // First vote from proposer
        _castPauseVote(proposalId);
        
        return proposalId;
    }

    function emergencyPause(IProofOfChange.FunctionGroup group) external {
        if (members[msg.sender] != IProofOfChange.MemberType.DAOMember) revert IProofOfChange.UnauthorizedDAO();
        
        PauseConfig storage config = pauseConfigs[group];
        config.isPaused = true;
        config.pauseEnds = block.timestamp + EMERGENCY_PAUSE_DURATION;
        config.requiresVoting = false;
        
        emit IProofOfChange.FunctionGroupPaused(group, config.pauseEnds);
    }

    function castPauseVote(bytes32 proposalId) external nonReentrant {
        if (members[msg.sender] != IProofOfChange.MemberType.DAOMember) revert IProofOfChange.UnauthorizedDAO();
        _castPauseVote(proposalId);
    }

    function _castPauseVote(bytes32 proposalId) internal {
        PauseVoting storage voting = pauseVotes[proposalId];
        if (voting.proposedAt == 0) revert IProofOfChange.PauseProposalNotFound();
        if (voting.hasVoted[msg.sender]) revert IProofOfChange.AlreadyVotedForPause();
        if (block.timestamp > voting.proposedAt + 1 days) revert IProofOfChange.PauseProposalExpired();

        voting.hasVoted[msg.sender] = true;
        voting.votesReceived++;

        emit IProofOfChange.PauseVoteCast(proposalId, msg.sender);

        if (voting.votesReceived >= voting.votesRequired && !voting.executed) {
            voting.executed = true;
            IProofOfChange.FunctionGroup group = IProofOfChange.FunctionGroup(uint8(uint256(proposalId) % 4)); // Extract group from proposalId
            
            PauseConfig storage config = pauseConfigs[group];
            config.isPaused = true;
            config.pauseEnds = block.timestamp + voting.duration;
            config.requiresVoting = true;
            
            emit IProofOfChange.FunctionGroupPaused(group, config.pauseEnds);
        }
    }

    function _unpause(IProofOfChange.FunctionGroup group) internal {
        PauseConfig storage config = pauseConfigs[group];
        config.isPaused = false;
        config.pauseEnds = 0;
        config.requiresVoting = false;
        
        emit IProofOfChange.FunctionGroupUnpaused(group);
    }

    // Emergency actions that can be performed during pause
    // should change to enum for gas efficiency
    function emergencyProjectAction(
        bytes32 projectId, 
        string calldata action,
        bytes calldata data
    ) external nonReentrant requiresEmergencyConsensus(
        keccak256(abi.encodePacked("emergencyAction", projectId, action))
    ) {
        if (members[msg.sender] != IProofOfChange.MemberType.DAOMember) revert IProofOfChange.UnauthorizedDAO();
        Project storage project = projects[projectId];
        if (project.proposer == address(0)) revert IProofOfChange.ProjectNotFound();

        bytes32 actionHash = keccak256(bytes(action));
        
        if (actionHash == keccak256(bytes("freeze"))) {
            _freezeProject(projectId, data);
        } else if (actionHash == keccak256(bytes("updatePhase"))) {
            _forceUpdatePhase(projectId, data);
        } else if (actionHash == keccak256(bytes("reassignProject"))) {
            _reassignProject(projectId, data);
        } else if (actionHash == keccak256(bytes("updateVotes"))) {
            _updateVoteResults(projectId, data);
        } else {
            revert IProofOfChange.InvalidEmergencyAction();
        }

        emit EmergencyActionExecuted(msg.sender, projectId, action);
    }

    function _freezeProject(bytes32 projectId, bytes calldata data) internal {
        uint256 duration = abi.decode(data, (uint256));
        
        if (duration < 1 hours || duration > 30 days) revert IProofOfChange.InvalidDuration();
        
        Project storage project = projects[projectId];
        project.status = ProjectStatus.Frozen;
        projectFrozenUntil[projectId] = block.timestamp + duration;
        
        emit ProjectAction(
            projectId, 
            msg.sender, 
            ProjectActionType.Frozen, 
            string(abi.encodePacked("Project frozen for ", duration.toString(), " seconds"))
        );
    }

    function _forceUpdatePhase(bytes32 projectId, bytes calldata data) internal {
        (IProofOfChange.VoteType newPhase, string memory reason) = abi.decode(data, (IProofOfChange.VoteType, string));
        
        Project storage project = projects[projectId];
        if (newPhase == project.currentPhase) revert IProofOfChange.InvalidPhase();
        
        // Update the project phase
        project.currentPhase = newPhase;
        
        emit ProjectAction(
            projectId, 
            msg.sender, 
            ProjectActionType.PhaseUpdated, 
            reason
        );
    }

    function setVotingPeriod(uint256 newVotingPeriod) external {
        if (members[msg.sender] != IProofOfChange.MemberType.DAOMember) 
            revert IProofOfChange.UnauthorizedDAO();
        if (newVotingPeriod < 1 days || newVotingPeriod > 30 days) 
            revert IProofOfChange.InvalidDuration();
        votingPeriod = newVotingPeriod;
    }

    function vote(bytes32 attestationUID, uint256 regionId, bool approve) 
        external 
        nonReentrant
        whenNotPaused(IProofOfChange.FunctionGroup.Voting) 
    {
        IProofOfChange.MemberType memberType = members[msg.sender];
        if (memberType == IProofOfChange.MemberType.NonMember) revert IProofOfChange.UnauthorizedDAO();
        
        Vote storage voteData = attestationVotes[attestationUID];
        if (voteData.hasVoted[msg.sender]) revert IProofOfChange.AlreadyVoted();
        
        // Verify attestation exists
        Attestation memory attestation = eas.getAttestation(attestationUID);
        if (attestation.schema != LOCATION_SCHEMA) revert IProofOfChange.InvalidAttestation();
        
        // Record vote
        voteData.hasVoted[msg.sender] = true;
        
        if (approve) {
            if (memberType == IProofOfChange.MemberType.SubDAOMember) {
                if (!regionSubDAOMembers[regionId][msg.sender]) revert IProofOfChange.SubDAOMemberNotFromRegion();
                voteData.subDaoVotesFor++;
            } else {
                voteData.daoVotesFor++;
            }
            
            // Check if enough votes received from both groups
            if (voteData.daoVotesFor >= voteData.daoVotesRequired && 
                voteData.subDaoVotesFor >= voteData.subDaoVotesRequired &&
                voteData.result == IProofOfChange.VoteResult.Pending) {
                voteData.result = IProofOfChange.VoteResult.Approved;
                emit IProofOfChange.AttestationApproved(attestationUID);
            }
        }
        
        emit IProofOfChange.VoteCast(attestationUID, msg.sender, memberType);
    }

    function initializeVoting(
        bytes32 attestationUID, 
        uint256 daoVotesNeeded,
        uint256 subDaoVotesNeeded
    ) public {
        if (members[msg.sender] != IProofOfChange.MemberType.DAOMember) revert IProofOfChange.UnauthorizedDAO();
        
        Vote storage voteData = attestationVotes[attestationUID];
        if (voteData.daoVotesRequired != 0) revert IProofOfChange.InvalidVoteState();
        
        // Verify attestation exists
        Attestation memory attestation = eas.getAttestation(attestationUID);
        if (attestation.schema != LOCATION_SCHEMA) revert IProofOfChange.InvalidAttestation();
        
        voteData.daoVotesRequired = daoVotesNeeded;
        voteData.subDaoVotesRequired = subDaoVotesNeeded;
        voteData.votingEnds = block.timestamp + votingPeriod;
        emit IProofOfChange.VotingInitialized(attestationUID, voteData.votingEnds);
    }

    // Keep the external version for other contracts to use
    function isApproved(bytes32 attestationUID) external view returns (bool) {
        return _isApproved(attestationUID);
    }

    // Add internal version for use within the contract
    function _isApproved(bytes32 attestationUID) internal view returns (bool) {
        return attestationVotes[attestationUID].result == IProofOfChange.VoteResult.Approved;
    }

    function isValid(
        // bytes32 attestationUID,
        address attester,
        bytes memory data
    ) external view returns (bool) {
        // Decode the attestation data
        (
            bytes32 projectId,
            string memory name,
            string memory description,
            string memory location,
            uint256 regionId,
            IProofOfChange.VoteType phase
        ) = abi.decode(data, (bytes32, string, string, string, uint256, IProofOfChange.VoteType));

        // Validate project exists
        Project storage project = projects[projectId];
        if (project.proposer == address(0)) return false;

        // Validate attester is the project proposer
        if (attester != project.proposer) return false;

        // Validate project phase matches
        if (phase != project.currentPhase) return false;

        // Validate non-empty strings
        if (bytes(name).length == 0 || 
            bytes(description).length == 0 || 
            bytes(location).length == 0) return false;

        // Validate region ID exists (assuming valid regions are > 0)
        if (regionId == 0) return false;

        return true;
    }

    function addDAOMember(address member) external {
        // Add access control as needed
        members[member] = IProofOfChange.MemberType.DAOMember;
        emit MemberAction(
            member,
            IProofOfChange.MemberType.DAOMember,  // new type
            IProofOfChange.MemberType.NonMember,  // previous type
            0,  // no region for DAO members
            false  // not a removal
        );
    }

    function addSubDAOMember(address member, uint256 regionId) external {
        // Add access control as needed
        members[member] = IProofOfChange.MemberType.SubDAOMember;
        regionSubDAOMembers[regionId][member] = true;
        emit MemberAction(
            member,
            IProofOfChange.MemberType.SubDAOMember,  // new type
            IProofOfChange.MemberType.NonMember,  // previous type
            regionId,
            false  // not a removal
        );
    }

    function finalizeVote(bytes32 attestationUID) external nonReentrant {
        Vote storage voteData = attestationVotes[attestationUID];
        if (voteData.votingEnds > block.timestamp) revert IProofOfChange.VotingPeriodNotEnded();
        if (voteData.isFinalized) revert IProofOfChange.VoteAlreadyFinalized();

        if (voteData.daoVotesFor >= voteData.daoVotesRequired && 
            voteData.subDaoVotesFor >= voteData.subDaoVotesRequired) {
            voteData.result = IProofOfChange.VoteResult.Approved;
            voteData.isFinalized = true;
            emit IProofOfChange.VoteFinalized(attestationUID, IProofOfChange.VoteResult.Approved);
        } else {
            voteData.result = IProofOfChange.VoteResult.Rejected;
            voteData.isFinalized = true;
            emit IProofOfChange.VoteFinalized(attestationUID, IProofOfChange.VoteResult.Rejected);
        }
    }

    function createProject(
        ProjectCreationData calldata data
    ) external nonReentrant returns (bytes32) {
        if (data.mediaTypes.length == 0 || data.mediaTypes.length != data.mediaData.length) {
            revert IProofOfChange.InvalidMediaData();
        }

        // Validate fund allocation and duration
        if (!_validateFundAllocation(data.phaseAllocations, data.requestedFunds)) {
            revert InvalidFundAllocation();
        }
        if (data.expectedDuration < 1 days || data.expectedDuration > 365 days) {
            revert InvalidDuration();
        }
        
        bytes32 projectId = keccak256(
            abi.encodePacked(
                data.name,
                block.timestamp,
                msg.sender
            )
        );

        // Create project with funding data
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

        // Initialize phase progress for Initial phase
        string[] memory initialMilestones = new string[](1);
        initialMilestones[0] = "Submit initial documentation";
        _initializePhaseProgress(
            projectId,
            IProofOfChange.VoteType.Initial,
            7 days, // Example duration
            true,   // Requires media
            initialMilestones
        );

        // Add media separately
        _addInitialMedia(
            projectId,
            data.mediaTypes,
            data.mediaData,
            data.mediaDescription
        );

        // Store project ID in user's projects and emit event
        userProjects[msg.sender].push(projectId);
        emit ProjectAction(
            projectId, 
            msg.sender, 
            ProjectActionType.Created, 
            data.name
        );

        // Create initial attestation
        createPhaseAttestation(projectId, IProofOfChange.VoteType.Initial);

        return projectId;
    }

    // Helper function to create project data
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
        newProject.name = name;
        newProject.description = description;
        newProject.location = location;
        newProject.regionId = regionId;
        newProject.proposer = msg.sender;
        newProject.currentPhase = IProofOfChange.VoteType.Initial;
        newProject.expectedDuration = expectedDuration;
        newProject.requestedFunds = requestedFunds;
        newProject.startDate = block.timestamp;
        newProject.fundsReleased = false;

        // Store phase allocations
        for (uint256 i = 0; i < phaseAllocations.length; i++) {
            newProject.phaseAllocations[IProofOfChange.VoteType(i)] = phaseAllocations[i];
        }

        emit ProjectFundingInitialized(
            projectId, 
            requestedFunds, 
            phaseAllocations
        );
    }

    // Helper function to add initial media
    function _addInitialMedia(
        bytes32 projectId,
        string[] calldata mediaTypes,
        string[] calldata mediaData,
        string calldata mediaDescription
    ) private {
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

    function createPhaseAttestation(
        bytes32 projectId,
        IProofOfChange.VoteType phase
    ) public nonReentrant returns (bytes32) {
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
                    recipient: address(0), // No specific recipient
                    expirationTime: 0, // No expiration
                    revocable: true,
                    refUID: bytes32(0), // No reference
                    data: attestationData,
                    value: 0 // No value being sent
                })
            })
        );

        // Store attestation UID for this phase
        project.attestationUIDs[phase] = attestationUID;

        emit IProofOfChange.PhaseAttestationCreated(projectId, phase, attestationUID);

        // Initialize voting for this attestation
        this.initializeVoting(
            attestationUID,
            3, // Example: require 3 DAO votes
            3  // Example: require 3 subDAO votes
        );

        return attestationUID;
    }

    function advanceToNextPhase(bytes32 projectId) external nonReentrant {
        Project storage project = projects[projectId];
        if (project.proposer == address(0)) revert IProofOfChange.ProjectNotFound();
        if (msg.sender != project.proposer) revert IProofOfChange.UnauthorizedProposer();

        // Get current phase attestation
        bytes32 currentAttestationUID = project.attestationUIDs[project.currentPhase];
        
        // Check if current phase is approved
        Vote storage currentVote = attestationVotes[currentAttestationUID];
        require(currentVote.result == IProofOfChange.VoteResult.Approved, "Current phase not approved");

        // Determine next phase
        if (project.currentPhase == IProofOfChange.VoteType.Initial) {
            project.currentPhase = IProofOfChange.VoteType.Progress;
        } else if (project.currentPhase == IProofOfChange.VoteType.Progress) {
            project.currentPhase = IProofOfChange.VoteType.Completion;
        } else {
            revert IProofOfChange.InvalidPhase();
        }

        // Create attestation for new phase
        createPhaseAttestation(projectId, project.currentPhase);
    }

    function getProjectDetails(bytes32 projectId) external view returns (
        string memory name,
        string memory description,
        string memory location,
        uint256 regionId,
        address proposer,
        IProofOfChange.VoteType currentPhase,
        bytes32 currentAttestationUID
    ) {
        Project storage project = projects[projectId];
        require(project.proposer != address(0), "Project not found");

        return (
            project.name,
            project.description,
            project.location,
            project.regionId,
            project.proposer,
            project.currentPhase,
            project.attestationUIDs[project.currentPhase]
        );
    }

    function getUserProjects(address user) external view returns (bytes32[] memory) {
        return userProjects[user];
    }

    function addPhaseMedia(
        bytes32 projectId,
        IProofOfChange.VoteType phase,
        string[] calldata mediaTypes,
        string[] calldata mediaData,
        string calldata mediaDescription
    ) external nonReentrant {
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

    function onAttest(
        Attestation calldata /* attestation */,
        uint256 /* value */
    ) internal virtual override returns (bool) {
        return true;
    }

    function onRevoke(
        Attestation calldata /* attestation */,
        uint256 /* value */
    ) internal virtual override returns (bool) {
        return true;
    }

    function removeDAOMember(address member) external timeLocked(
        keccak256(abi.encodePacked("removeDAOMember", member))
    ) {
        if (members[msg.sender] != IProofOfChange.MemberType.DAOMember) revert IProofOfChange.UnauthorizedDAO();
        if (members[member] == IProofOfChange.MemberType.NonMember) revert IProofOfChange.MemberNotFound();
        
        IProofOfChange.MemberType previousType = members[member];
        members[member] = IProofOfChange.MemberType.NonMember;
        
        // If they were a subDAO member, remove region access
        if (previousType == IProofOfChange.MemberType.SubDAOMember) {
            for (uint256 i = 0; i < 100; i++) { // Assuming reasonable number of regions
                if (regionSubDAOMembers[i][member]) {
                    regionSubDAOMembers[i][member] = false;
                }
            }
        }
        
        emit MemberAction(
            member,
            IProofOfChange.MemberType.NonMember,  // new type
            previousType,  // previous type
            0,  // no region for removal
            true  // is removal
        );
    }

    function updateMember(
        address member,
        IProofOfChange.MemberType newType,
        uint256 regionId
    ) external {
        if (members[msg.sender] != IProofOfChange.MemberType.DAOMember) revert IProofOfChange.UnauthorizedDAO();
        if (members[member] == IProofOfChange.MemberType.NonMember) revert IProofOfChange.MemberNotFound();
        
        IProofOfChange.MemberType previousType = members[member];
        members[member] = newType;
        
        // Handle subDAO region membership
        if (newType == IProofOfChange.MemberType.SubDAOMember) {
            regionSubDAOMembers[regionId][member] = true;
        } else if (previousType == IProofOfChange.MemberType.SubDAOMember) {
            // Remove all region access if no longer a subDAO member
            for (uint256 i = 0; i < 100; i++) {
                if (regionSubDAOMembers[i][member]) {
                    regionSubDAOMembers[i][member] = false;
                }
            }
        }
        
        emit MemberAction(
            member,
            newType,          // new type
            previousType,     // previous type
            regionId,
            false            // not a removal
        );
    }

    function _reassignProject(bytes32 projectId, bytes calldata data) internal {
        (address newProposer, address[] memory newValidators) = abi.decode(data, (address, address[]));
        
        if (newProposer == address(0) || newValidators.length == 0) revert IProofOfChange.InvalidAddresses();
        
        Project storage project = projects[projectId];
        project.proposer = newProposer;
        
        // Update user projects mapping
        userProjects[newProposer].push(projectId);
        
        emit ProjectAction(
            projectId, 
            msg.sender, 
            ProjectActionType.Reassigned, 
            "Project reassigned"
        );
    }

    function _updateVoteResults(bytes32 projectId, bytes calldata data) internal {
        bytes32[] memory attestationUIDs = abi.decode(data, (bytes32[]));
        
        Project storage project = projects[projectId];
        if (project.proposer == address(0)) revert IProofOfChange.ProjectNotFound();
        
        // Update vote results for each attestation
        for (uint256 i = 0; i < attestationUIDs.length; i++) {
            Vote storage voteData = attestationVotes[attestationUIDs[i]];
            if (voteData.votingEnds == 0) revert IProofOfChange.InvalidVoteData();
            
            // Reset vote data
            voteData.daoVotesFor = 0;
            voteData.daoVotesAgainst = 0;
            voteData.subDaoVotesFor = 0;
            voteData.subDaoVotesAgainst = 0;
            voteData.isFinalized = false;
            voteData.result = IProofOfChange.VoteResult.Pending;
        }
        
        emit IProofOfChange.VotesUpdated(projectId, attestationUIDs);
    }

    function updateProjectStatus(bytes32 projectId, ProjectStatus newStatus) external 
        whenNotPaused(IProofOfChange.FunctionGroup.ProjectManagement) 
    {
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

    function getProjectStatus(bytes32 projectId) external view returns (ProjectStatus) {
        return projects[projectId].status;
    }

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
        progress.milestones = milestones;
    }

    function isProjectDelayed(bytes32 projectId) external view returns (bool) {
        Project storage project = projects[projectId];
        if (project.proposer == address(0)) revert IProofOfChange.ProjectNotFound();
        
        PhaseProgress storage progress = project.phaseProgress[project.currentPhase];
        return block.timestamp > progress.targetEndTime && !progress.isComplete;
    }

    function updateMilestone(
        bytes32 projectId,
        string calldata milestone,
        bool completed
    ) external nonReentrant whenNotPaused(IProofOfChange.FunctionGroup.ProjectManagement) {
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

    function getPhaseProgress(
        bytes32 projectId,
        IProofOfChange.VoteType phase
    ) external view returns (
        uint256 startTime,
        uint256 targetEndTime,
        bool requiresMedia,
        bool isComplete,
        string[] memory milestones,
        uint256 completedMilestonesCount
    ) {
        Project storage project = projects[projectId];
        if (project.proposer == address(0)) revert IProofOfChange.ProjectNotFound();
        
        PhaseProgress storage progress = project.phaseProgress[phase];
        
        uint256 completed = 0;
        for (uint i = 0; i < progress.milestones.length; i++) {
            if (progress.completedMilestones[progress.milestones[i]]) {
                completed++;
            }
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

    // Add new modifier for timelocked operations
    modifier timeLocked(bytes32 operationId) {
        if (pendingOperations[operationId] == 0) {
            pendingOperations[operationId] = block.timestamp + TIMELOCK_PERIOD;
            emit OperationQueued(operationId);
            revert IProofOfChange.OperationTimelocked(operationId);
        }
        require(block.timestamp >= pendingOperations[operationId], "Timelock active");
        delete pendingOperations[operationId];
        _;
    }

    // Add new modifier for emergency operations
    modifier requiresEmergencyConsensus(bytes32 operationId) {
        require(isEmergencyAdmin(msg.sender), "Not emergency admin");
        emergencyApprovals[operationId][msg.sender] = true;
        
        uint256 approvalCount = 0;
        for (uint256 i = 0; i < emergencyAdmins.length; i++) {
            if (emergencyApprovals[operationId][emergencyAdmins[i]]) {
                approvalCount++;
            }
        }
        
        require(approvalCount >= EMERGENCY_THRESHOLD, "Insufficient approvals");
        _;
    }

    // Add helper function to check emergency admin status
    function isEmergencyAdmin(address account) public view returns (bool) {
        for (uint256 i = 0; i < emergencyAdmins.length; i++) {
            if (emergencyAdmins[i] == account) {
                return true;
            }
        }
        return false;
    }

    function _validateFundAllocation(uint256[] memory phaseAllocations, uint256 totalFunds) 
        internal 
        pure 
        returns (bool) 
    {
        if (phaseAllocations.length != 3) return false;
        
        uint256 total = 0;
        for (uint256 i = 0; i < phaseAllocations.length; i++) {
            total += phaseAllocations[i];
        }
        
        return total == totalFunds;
    }

    function releasePhaseFunds(bytes32 projectId, IProofOfChange.VoteType phase) 
        external 
        nonReentrant 
        whenNotPaused(IProofOfChange.FunctionGroup.FundManagement) 
    {
        Project storage project = projects[projectId];
        
        if (project.proposer == address(0)) revert IProofOfChange.ProjectNotFound();
        if (project.status != ProjectStatus.Completed) revert IProofOfChange.ProjectNotComplete();
        
        bytes32 attestationUID = project.attestationUIDs[phase];
        if (!_isApproved(attestationUID)) revert IProofOfChange.PhaseNotApproved();
        if (phaseFundsReleased[projectId][phase]) revert IProofOfChange.FundsAlreadyReleased();
        
        uint256 allocation = project.phaseAllocations[phase];
        phaseFundsReleased[projectId][phase] = true;
        
        (bool success, ) = project.proposer.call{value: allocation}("");
        require(success, "Fund transfer failed");
        
        emit PhaseFundsReleased(
            projectId,
            phase,
            project.proposer,
            allocation,
            block.timestamp
        );
    }

    function getProjectFinancials(bytes32 projectId) 
        external 
        view 
        returns (
            uint256 totalRequested,
            uint256 initialPhaseAmount,
            uint256 progressPhaseAmount,
            uint256 completionPhaseAmount,
            bool[] memory phasesFunded
        ) 
    {
        Project storage project = projects[projectId];
        bool[] memory funded = new bool[](3);
        
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

}
