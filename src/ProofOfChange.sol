// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IEAS, Attestation, AttestationRequest, AttestationRequestData} from "lib/eas-contracts/contracts/IEAS.sol";
import {SchemaResolver} from "lib/eas-contracts/contracts/resolver/SchemaResolver.sol";
import {IProofOfChange} from "./Interfaces/IProofOfChange.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract ProofOfChange is SchemaResolver, IProofOfChange, ReentrancyGuard {
    // Constants
    bytes32 public constant LOCATION_SCHEMA = 0xba4171c92572b1e4f241d044c32cdf083be9fd946b8766977558ca6378c824e2;
    
    // Structs
    struct Project {
        string name;
        string description;
        string location;
        uint256 regionId;
        address proposer;
        IProofOfChange.VoteType currentPhase;
        mapping(IProofOfChange.VoteType => Media) media;
        mapping(IProofOfChange.VoteType => bytes32) attestationUIDs;
        bool hasInitialMedia;
        bool isActive;
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

    constructor(address easRegistry, address[] memory initialDAOMembers) SchemaResolver(IEAS(easRegistry)) {
        eas = IEAS(easRegistry);
        minimumPauseVotes = (initialDAOMembers.length * 2) / 3; // 66% of initial DAO members
        for (uint256 i = 0; i < initialDAOMembers.length; i++) {
            members[initialDAOMembers[i]] = IProofOfChange.MemberType.DAOMember;
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
    function emergencyProjectAction(
        bytes32 projectId, 
        string calldata action,
        bytes calldata data
    ) external nonReentrant {
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
        
        // Validate duration (between 1 hour and 30 days)
        if (duration < 1 hours || duration > 30 days) revert IProofOfChange.InvalidDuration();
        
        projectFrozenUntil[projectId] = block.timestamp + duration;
        
        emit IProofOfChange.ProjectFrozen(projectId, duration, msg.sender);
    }

    function _forceUpdatePhase(bytes32 projectId, bytes calldata data) internal {
        (IProofOfChange.VoteType newPhase, string memory reason) = abi.decode(data, (IProofOfChange.VoteType, string));
        
        Project storage project = projects[projectId];
        if (newPhase == project.currentPhase) revert IProofOfChange.InvalidPhase();
        
        // Update the project phase
        project.currentPhase = newPhase;
        
        emit IProofOfChange.PhaseForceUpdated(projectId, newPhase, reason);
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

    function isApproved(bytes32 attestationUID) external view returns (bool) {
        return attestationVotes[attestationUID].result == IProofOfChange.VoteResult.Approved;
    }

    function isValid(
        bytes32 /* attestationUID */,
        address /* attester */,
        bytes memory /* data */
    ) external pure returns (bool) {
        // Basic schema validation
        return true;
    }

    function addDAOMember(address member) external {
        // Add access control as needed
        members[member] = IProofOfChange.MemberType.DAOMember;
        emit IProofOfChange.MemberAdded(member, IProofOfChange.MemberType.DAOMember, 0);
    }

    function addSubDAOMember(address member, uint256 regionId) external {
        // Add access control as needed
        members[member] = IProofOfChange.MemberType.SubDAOMember;
        regionSubDAOMembers[regionId][member] = true;
        emit IProofOfChange.MemberAdded(member, IProofOfChange.MemberType.SubDAOMember, regionId);
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
        
        bytes32 projectId = keccak256(
            abi.encodePacked(
                data.name,
                block.timestamp,
                msg.sender
            )
        );

        // Create project first
        _createProjectData(
            projectId, 
            data.name, 
            data.description, 
            data.location, 
            data.regionId
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
        emit IProofOfChange.ProjectCreated(projectId, msg.sender, data.name, data.regionId);

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
        uint256 regionId
    ) private {
        Project storage newProject = projects[projectId];
        newProject.name = name;
        newProject.description = description;
        newProject.location = location;
        newProject.regionId = regionId;
        newProject.proposer = msg.sender;
        newProject.currentPhase = IProofOfChange.VoteType.Initial;
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

    function removeDAOMember(address member) external {
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
        
        emit IProofOfChange.MemberRemoved(member, previousType);
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
        
        emit IProofOfChange.MemberUpdated(member, previousType, newType, regionId);
    }

    function _reassignProject(bytes32 projectId, bytes calldata data) internal {
        (address newProposer, address[] memory newValidators) = abi.decode(data, (address, address[]));
        
        if (newProposer == address(0) || newValidators.length == 0) revert IProofOfChange.InvalidAddresses();
        
        Project storage project = projects[projectId];
        project.proposer = newProposer;
        
        // Update user projects mapping
        userProjects[newProposer].push(projectId);
        
        emit IProofOfChange.ProjectReassigned(projectId, newProposer, newValidators);
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
}
