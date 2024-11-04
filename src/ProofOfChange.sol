// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IEAS, Attestation, AttestationRequest, AttestationRequestData} from "lib/eas-contracts/contracts/IEAS.sol";
import {SchemaResolver} from "lib/eas-contracts/contracts/resolver/SchemaResolver.sol";

contract ProofOfChange is SchemaResolver {
    // Constants
    bytes32 public constant LOCATION_SCHEMA = 0xba4171c92572b1e4f241d044c32cdf083be9fd946b8766977558ca6378c824e2;
    
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
    
    struct Vote {
        uint256 daoVotesFor;
        uint256 daoVotesAgainst;
        uint256 subDaoVotesFor;
        uint256 subDaoVotesAgainst;
        uint256 daoVotesRequired;
        uint256 subDaoVotesRequired;
        uint256 votingEnds;        // Timestamp when voting period ends
        mapping(address => bool) hasVoted;
        bool isFinalized;
        VoteResult result;
    }
    
    struct Media {
        string[] mediaTypes;      // Array of MIME types
        string[] mediaData;       // Array of CIDs or media identifiers
        uint256 timestamp;        // When the media was added
        string description;       // Description of the media
        bool verified;            // Whether the media has been verified
    }
    
    struct Project {
        string name;
        string description;
        string location;
        uint256 regionId;
        address proposer;
        VoteType currentPhase;
        mapping(VoteType => bytes32) attestationUIDs;    // Maps phase to attestation
        mapping(VoteType => Media) media;                // Maps phase to media data
        bool hasInitialMedia;                            // Check if initial media is provided
    }
    
    struct ProjectCreationData {
        string name;
        string description;
        string location;
        uint256 regionId;
        string[] mediaTypes;
        string[] mediaData;
        string mediaDescription;
    }
    
    // State variables
    mapping(bytes32 => Vote) public attestationVotes;
    mapping(address => MemberType) public members;
    mapping(uint256 => mapping(address => bool)) public regionSubDAOMembers;
    IEAS private immutable eas;
    mapping(bytes32 => Project) public projects;
    mapping(address => bytes32[]) public userProjects;
    
    // Events
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
    event MemberRemoved(address member, MemberType previousType);
    event MemberUpdated(address member, MemberType previousType, MemberType newType, uint256 regionId);
    
    // Errors
    error InvalidAttestation();
    error UnauthorizedDAO();
    error AlreadyVoted();
    error AttestationNotFound();
    error InvalidVoteState();
    error SubDAOMemberNotFromRegion();
    error VotingPeriodEnded();
    error VotingPeriodNotEnded();
    error VoteAlreadyFinalized();
    error InvalidPhase();
    error UnauthorizedProposer();
    error ProjectNotFound();
    error NoInitialMedia(); 
    error MediaAlreadyExists();
    error InvalidMediaData();
    error MediaTypeMismatch();
    error MemberNotFound();
    
    // Cool-down period duration
    uint256 public votingPeriod = 7 days; // Default value
    
    constructor(address easRegistry, address[] memory initialDAOMembers) SchemaResolver(IEAS(easRegistry)) {
        eas = IEAS(easRegistry);
        for (uint256 i = 0; i < initialDAOMembers.length; i++) {
            members[initialDAOMembers[i]] = MemberType.DAOMember;
        }
    }

    function setVotingPeriod(uint256 newVotingPeriod) external {
        if (members[msg.sender] != MemberType.DAOMember) revert UnauthorizedDAO();
        votingPeriod = newVotingPeriod;
    }

    function vote(bytes32 attestationUID, uint256 regionId, bool approve) external {
        MemberType memberType = members[msg.sender];
        if (memberType == MemberType.NonMember) revert UnauthorizedDAO();
        
        Vote storage voteData = attestationVotes[attestationUID];
        if (voteData.hasVoted[msg.sender]) revert AlreadyVoted();
        
        // Verify attestation exists
        Attestation memory attestation = eas.getAttestation(attestationUID);
        if (attestation.schema != LOCATION_SCHEMA) revert InvalidAttestation();
        
        // Record vote
        voteData.hasVoted[msg.sender] = true;
        
        if (approve) {
            if (memberType == MemberType.SubDAOMember) {
                if (!regionSubDAOMembers[regionId][msg.sender]) revert SubDAOMemberNotFromRegion();
                voteData.subDaoVotesFor++;
            } else {
                voteData.daoVotesFor++;
            }
            
            // Check if enough votes received from both groups
            if (voteData.daoVotesFor >= voteData.daoVotesRequired && 
                voteData.subDaoVotesFor >= voteData.subDaoVotesRequired &&
                voteData.result == VoteResult.Pending) {
                voteData.result = VoteResult.Approved;
                emit AttestationApproved(attestationUID);
            }
        }
        
        emit VoteCast(attestationUID, msg.sender, memberType);
    }

    function initializeVoting(
        bytes32 attestationUID, 
        uint256 daoVotesNeeded,
        uint256 subDaoVotesNeeded
    ) public {
        if (members[msg.sender] != MemberType.DAOMember) revert UnauthorizedDAO();
        
        Vote storage voteData = attestationVotes[attestationUID];
        if (voteData.daoVotesRequired != 0) revert InvalidVoteState();
        
        // Verify attestation exists
        Attestation memory attestation = eas.getAttestation(attestationUID);
        if (attestation.schema != LOCATION_SCHEMA) revert InvalidAttestation();
        
        voteData.daoVotesRequired = daoVotesNeeded;
        voteData.subDaoVotesRequired = subDaoVotesNeeded;
        voteData.votingEnds = block.timestamp + votingPeriod;
        emit VotingInitialized(attestationUID, voteData.votingEnds);
    }

    function isApproved(bytes32 attestationUID) external view returns (bool) {
        return attestationVotes[attestationUID].result == VoteResult.Approved;
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
        members[member] = MemberType.DAOMember;
        emit MemberAdded(member, MemberType.DAOMember, 0);
    }

    function addSubDAOMember(address member, uint256 regionId) external {
        // Add access control as needed
        members[member] = MemberType.SubDAOMember;
        regionSubDAOMembers[regionId][member] = true;
        emit MemberAdded(member, MemberType.SubDAOMember, regionId);
    }

    function finalizeVote(bytes32 attestationUID) external {
        Vote storage voteData = attestationVotes[attestationUID];
        if (voteData.votingEnds > block.timestamp) revert VotingPeriodNotEnded();
        if (voteData.isFinalized) revert VoteAlreadyFinalized();

        if (voteData.daoVotesFor >= voteData.daoVotesRequired && 
            voteData.subDaoVotesFor >= voteData.subDaoVotesRequired) {
            voteData.result = VoteResult.Approved;
            voteData.isFinalized = true;
            emit VoteFinalized(attestationUID, VoteResult.Approved);
        } else {
            voteData.result = VoteResult.Rejected;
            voteData.isFinalized = true;
            emit VoteFinalized(attestationUID, VoteResult.Rejected);
        }
    }

    function createProject(
        ProjectCreationData calldata data
    ) external returns (bytes32) {
        if (data.mediaTypes.length == 0 || data.mediaTypes.length != data.mediaData.length) {
            revert InvalidMediaData();
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
        emit ProjectCreated(projectId, msg.sender, data.name, data.regionId);

        // Create initial attestation
        createPhaseAttestation(projectId, VoteType.Initial);

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
        newProject.currentPhase = VoteType.Initial;
    }

    // Helper function to add initial media
    function _addInitialMedia(
        bytes32 projectId,
        string[] calldata mediaTypes,
        string[] calldata mediaData,
        string calldata mediaDescription
    ) private {
        Project storage project = projects[projectId];
        project.media[VoteType.Initial] = Media({
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
        VoteType phase
    ) public returns (bytes32) {
        Project storage project = projects[projectId];
        if (project.proposer == address(0)) revert ProjectNotFound();
        if (msg.sender != project.proposer) revert UnauthorizedProposer();
        if (phase != project.currentPhase) revert InvalidPhase();

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

        emit PhaseAttestationCreated(projectId, phase, attestationUID);

        // Initialize voting for this attestation
        this.initializeVoting(
            attestationUID,
            3, // Example: require 3 DAO votes
            3  // Example: require 3 subDAO votes
        );

        return attestationUID;
    }

    function advanceToNextPhase(bytes32 projectId) external {
        Project storage project = projects[projectId];
        if (project.proposer == address(0)) revert ProjectNotFound();
        if (msg.sender != project.proposer) revert UnauthorizedProposer();

        // Get current phase attestation
        bytes32 currentAttestationUID = project.attestationUIDs[project.currentPhase];
        
        // Check if current phase is approved
        Vote storage currentVote = attestationVotes[currentAttestationUID];
        require(currentVote.result == VoteResult.Approved, "Current phase not approved");

        // Determine next phase
        if (project.currentPhase == VoteType.Initial) {
            project.currentPhase = VoteType.Progress;
        } else if (project.currentPhase == VoteType.Progress) {
            project.currentPhase = VoteType.Completion;
        } else {
            revert InvalidPhase();
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
        VoteType currentPhase,
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
        VoteType phase,
        string[] calldata mediaTypes,
        string[] calldata mediaData,
        string calldata mediaDescription
    ) external {
        Project storage project = projects[projectId];
        if (project.proposer == address(0)) revert ProjectNotFound();
        if (msg.sender != project.proposer) revert UnauthorizedProposer();
        if (phase != project.currentPhase) revert InvalidPhase();
        if (mediaTypes.length == 0 || mediaTypes.length != mediaData.length) revert InvalidMediaData();
        if (project.media[phase].mediaTypes.length > 0) revert MediaAlreadyExists();

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
        if (members[msg.sender] != MemberType.DAOMember) revert UnauthorizedDAO();
        if (members[member] == MemberType.NonMember) revert MemberNotFound();
        
        MemberType previousType = members[member];
        members[member] = MemberType.NonMember;
        
        // If they were a subDAO member, remove region access
        if (previousType == MemberType.SubDAOMember) {
            for (uint256 i = 0; i < 100; i++) { // Assuming reasonable number of regions
                if (regionSubDAOMembers[i][member]) {
                    regionSubDAOMembers[i][member] = false;
                }
            }
        }
        
        emit MemberRemoved(member, previousType);
    }

    function updateMember(
        address member,
        MemberType newType,
        uint256 regionId
    ) external {
        if (members[msg.sender] != MemberType.DAOMember) revert UnauthorizedDAO();
        if (members[member] == MemberType.NonMember) revert MemberNotFound();
        
        MemberType previousType = members[member];
        members[member] = newType;
        
        // Handle subDAO region membership
        if (newType == MemberType.SubDAOMember) {
            regionSubDAOMembers[regionId][member] = true;
        } else if (previousType == MemberType.SubDAOMember) {
            // Remove all region access if no longer a subDAO member
            for (uint256 i = 0; i < 100; i++) {
                if (regionSubDAOMembers[i][member]) {
                    regionSubDAOMembers[i][member] = false;
                }
            }
        }
        
        emit MemberUpdated(member, previousType, newType, regionId);
    }
}
