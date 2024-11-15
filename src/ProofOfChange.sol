// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@eas/IEAS.sol";
import "@eas/resolver/SchemaResolver.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title ProofOfChange
 * @dev A decentralized contract for managing and verifying environmental conservation projects
 * through satellite imagery and on-chain attestations.
 *
 * The contract implements a three-phase project lifecycle:
 * 1. Initial Phase (25% funding)
 * 2. Progress Phase (25% funding) 
 * 3. Completion Phase (50% funding)
 *
 * Each phase requires:
 * - State proof submission (attestation + satellite image)
 * - Voting approval from both DAO and SubDAO members
 * - Successful vote completion to release funds
 *
 * @notice This contract handles project creation, voting, fund management, and membership control

 */
contract ProofOfChange is ReentrancyGuard {

    // ============ Structs ============
    struct VotingConfig {
        uint256 votingPeriod;      // How long voting lasts
    }

    struct Project {
        // Core project info
        address proposer;
        string location;           
        uint256 requestedFunds;
        uint256 regionId;
        uint256 estimatedDuration; // Duration in seconds
        uint256 startTime;         // When project begins (after initial phase approval)
        
        // Status
        bool isActive;
        uint8 currentPhase;       // 0: Initial, 1: Progress, 2: Completion
    }
  
    struct Vote {
        uint128 daoFor;
        uint128 daoAgainst;
        uint128 subDaoFor;
        uint128 subDaoAgainst;
        uint256 startTime;
        mapping(address => bool) hasVoted;
        bool finalized;
        bool approved;
    }
 
    struct StateProof {
        bytes32 attestationUID;
        bytes32 imageHash;
        uint256 timestamp;
        Vote vote;
        bool completed;
    }

    
    struct ProjectDetails {
        address proposer;
        string location;
        uint256 requestedFunds;
        uint256 regionId;
        uint256 estimatedDuration;
        uint256 startTime;
        uint256 elapsedTime;
        uint256 remainingTime;
        bool isActive;
        uint8 currentPhase;
    }

    // ============ Events ============

    event VotingConfigUpdated(uint256 newVotingPeriod);
    event ProjectCreated(bytes32 indexed projectId, address indexed proposer, uint256 requestedFunds, uint256 estimatedDuration);
    event StateProofSubmitted(bytes32 indexed projectId, uint8 indexed phase, bytes32 attestationUID, bytes32 imageHash);
    event VoteCast(bytes32 indexed projectId, uint8 indexed phase, address indexed voter, bool isDAO, bool support);
    event VotingStarted(bytes32 indexed projectId, uint8 indexed phase, uint256 startTime, uint256 endTime);
    event VotingCompleted(bytes32 indexed projectId, uint8 indexed phase, bool approved);
    event PhaseCompleted(bytes32 indexed projectId, uint8 indexed phase, uint256 timestamp);
    event FundsReleased(bytes32 indexed projectId, uint8 indexed phase, uint256 amount);
    event DAOMemberAdded(address indexed member);
    event DAOMemberRemoved(address indexed member);
    event SubDAOMemberAdded(address indexed member, uint256 indexed regionId);
    event SubDAOMemberRemoved(address indexed member, uint256 indexed regionId);

    // ============ State Variables ============

    mapping(bytes32 => Project) public projects;
    mapping(bytes32 => StateProof) private stateProofs;
    mapping(address => bool) private daoMembers;
    mapping(uint256 => mapping(address => bool)) private subDaoMembers; // regionId => member => isMember

    VotingConfig public votingConfig;
    address public admin;

    /**
     * @notice Contract constructor
     * @param initialVotingPeriod Initial duration of voting periods
     */
    constructor(uint256 initialVotingPeriod) {
        votingConfig.votingPeriod = initialVotingPeriod;
        admin = msg.sender;
    }

    // ============ Modifiers ============

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    modifier onlyDAOMember() {
        require(daoMembers[msg.sender], "Not DAO member");
        _;
    }

    modifier onlySubDAOMember(uint256 regionId) {
        require(subDaoMembers[regionId][msg.sender], "Not SubDAO member");
        _;
    }

    modifier onlyDAOOrSubDAOMember(uint256 regionId) {
        bool isDAO = daoMembers[msg.sender];
        require(isDAO || subDaoMembers[regionId][msg.sender], "Not authorized to vote");
        _;
    }

    // ============ Project Management Functions ============

    /**
     * @notice Create initial project and state proof
     * @param attestationUID Initial Logbook attestation
     * @param imageHash Initial satellite image hash
     * @param location Project location
     * @param requestedFunds Amount of funds requested
     * @param regionId Geographic region ID
     * @param estimatedDuration Estimated project duration in seconds
     */
    function createProject(
        bytes32 attestationUID,
        bytes32 imageHash,
        string calldata location,
        uint256 requestedFunds,
        uint256 regionId,
        uint256 estimatedDuration
    ) external payable nonReentrant returns (bytes32) {
        require(msg.value == requestedFunds, "Incorrect funds sent");
        require(attestationUID != bytes32(0), "Invalid attestation");
        require(imageHash != bytes32(0), "Invalid image hash");
        require(estimatedDuration > 0 && estimatedDuration <= 365 days, "Invalid duration");
        
        bytes32 projectId = keccak256(abi.encodePacked(msg.sender, attestationUID, block.timestamp));
        _createProjectInternal(projectId, msg.sender, location, requestedFunds, regionId, estimatedDuration);
        _createInitialStateProof(projectId, attestationUID, imageHash);
        
        emit ProjectCreated(projectId, msg.sender, requestedFunds, estimatedDuration);
        return projectId;
    }

    // ============ State Proof Functions ============

    /**
     * @notice Submit a new state proof for progress/completion
     */
    function submitStateProof(
        bytes32 projectId,
        bytes32 attestationUID,
        bytes32 imageHash
    ) external nonReentrant {
        Project storage project = projects[projectId];
        require(project.isActive, "Project not active");
        require(msg.sender == project.proposer, "Not proposer");
        
        uint8 currentPhase = project.currentPhase;
        require(currentPhase < 2, "Project completed");
        
        _validateAndUpdateStateProof(projectId, currentPhase, attestationUID, imageHash);
        
        emit StateProofSubmitted(projectId, currentPhase + 1, attestationUID, imageHash);
        project.currentPhase = currentPhase + 1;
    }

    // ============ Voting Functions ============

    /**
     * @notice Start voting period for current phase
     */
    function startVoting(bytes32 projectId) external {
        Project storage project = projects[projectId];
        require(project.isActive, "Project not active");
        require(msg.sender == project.proposer, "Not proposer");

        bytes32 stateProofId = generateStateProofId(projectId, project.currentPhase);
        StateProof storage stateProof = stateProofs[stateProofId];
        
        require(stateProof.attestationUID != bytes32(0), "No attestation");
        require(stateProof.vote.startTime == 0, "Voting already started");
        // Project could technically still be marked as active even if it's in phase 2 (completion) or beyond 
        require(project.currentPhase <= 2, "Project completed");
        // sets the start time of the voting period to the current block timestamp
        // used to calculate when voting ends (startTime + votingConfig.votingPeriod)
        // used in the castVote function to verify votes are cast within the valid voting window 
        uint256 startTime = block.timestamp;
        stateProof.vote.startTime = startTime;

        emit VotingStarted(
            projectId,
            project.currentPhase,
            startTime,
            startTime + votingConfig.votingPeriod
        );
    }

    /**
     * @notice Cast vote for current phase
     */
    function castVote(bytes32 projectId, bool support) external onlyDAOOrSubDAOMember(projects[projectId].regionId) {
        bool isDAO = daoMembers[msg.sender];
        Project storage project = projects[projectId];
        require(project.isActive, "Project not active");

        bytes32 stateProofId = generateStateProofId(projectId, project.currentPhase);
        StateProof storage stateProof = stateProofs[stateProofId];
        Vote storage vote = stateProof.vote;

        require(vote.startTime != 0, "Voting not started");
        require(!vote.finalized, "Voting ended");
        require(!vote.hasVoted[msg.sender], "Already voted");
        // time-based check that verifies if the voting period is still active 
        // for situations where the voting period has ended but the vote hasn't been finalized yet 
        require(
            block.timestamp <= vote.startTime + votingConfig.votingPeriod,
            "Voting period ended"
        );

        if (isDAO) {
            if (support) vote.daoFor++; 
            else vote.daoAgainst++;
        } else {
            if (support) vote.subDaoFor++; 
            else vote.subDaoAgainst++;
        }

        emit VoteCast(projectId, project.currentPhase, msg.sender, isDAO, support);
    }

    /**
     * @notice Finalize voting and process results
     */
    function finalizeVoting(bytes32 projectId) external nonReentrant {
        Project storage project = projects[projectId];
        require(project.isActive, "Project not active");

        bytes32 stateProofId = generateStateProofId(projectId, project.currentPhase);
        StateProof storage stateProof = stateProofs[stateProofId];
        Vote storage vote = stateProof.vote;

        require(vote.startTime != 0, "Voting not started");
        require(!vote.finalized, "Already finalized");
        require(
            block.timestamp > vote.startTime + votingConfig.votingPeriod,
            "Voting period not ended"
        );
        // approval based on majority votes 
        bool daoApproved = vote.daoFor > vote.daoAgainst;
        bool subDaoApproved = vote.subDaoFor > vote.subDaoAgainst;

        vote.finalized = true;
        vote.approved = daoApproved && subDaoApproved;

        emit VotingCompleted(projectId, project.currentPhase, vote.approved);

        if (vote.approved) {
            completePhase(projectId);
            // Add special handling for completion phase to prevent any further state proofs or voting from being initiated on completed projects 
            if (project.currentPhase == 2) {
                project.isActive = false; // Prevent any further actions on completed project
            }
        }
    }

    // ============ Fund Management Functions ============

    /**
     * @notice Complete phase and release funds
     */
    function completePhase(bytes32 projectId) internal {
        Project storage project = projects[projectId];
        bytes32 stateProofId = generateStateProofId(projectId, project.currentPhase);
        StateProof storage stateProof = stateProofs[stateProofId];

        stateProof.completed = true;

        // Set project start time when initial phase (0) is approved
        // This marks the official beginning of the project timeline
        if (project.currentPhase == 0) {
            project.startTime = block.timestamp;
        }

        emit PhaseCompleted(projectId, project.currentPhase, block.timestamp);

        uint256 amount = calculatePhaseAmount(project.requestedFunds, project.currentPhase);
        (bool success, ) = project.proposer.call{value: amount}("");
        require(success, "Fund transfer failed");
        
        emit FundsReleased(projectId, project.currentPhase, amount);
    }

    /**
     * @notice Calculate funds to release for phase
     */
    function calculatePhaseAmount(uint256 totalFunds, uint8 phase) internal pure returns (uint256) {
        if (phase == 0) return totalFunds * 25 / 100; // Initial: 25%
        if (phase == 1) return totalFunds * 25 / 100; // Progress: 25%
        if (phase == 2) return totalFunds * 50 / 100; // Completion: 50%
        return 0;
    }

    // ============ View Functions ============

    /**
     * @notice Get project details including duration info
     */
    function getProjectDetails(bytes32 projectId) external view returns (ProjectDetails memory) {
        Project storage project = projects[projectId];
        
        // Calculate time-related values
        uint256 elapsed = project.startTime > 0 ? 
            block.timestamp - project.startTime : 0;
            
        uint256 remaining = project.startTime > 0 ? 
            project.estimatedDuration > elapsed ? 
                project.estimatedDuration - elapsed : 0 
            : project.estimatedDuration;


        return ProjectDetails({
            proposer: project.proposer,
            location: project.location,
            requestedFunds: project.requestedFunds,
            regionId: project.regionId,
            estimatedDuration: project.estimatedDuration,
            startTime: project.startTime,
            elapsedTime: elapsed,
            remainingTime: remaining,
            isActive: project.isActive,
            currentPhase: project.currentPhase
        });
    }

    /**
     * @notice Get state proof details
     */
    function getStateProofDetails(bytes32 projectId, uint8 phase) external view returns (
        bytes32 attestationUID,
        bytes32 imageHash,
        uint256 timestamp,
        bool completed
    ) {
        bytes32 stateProofId = generateStateProofId(projectId, phase);
        StateProof storage proof = stateProofs[stateProofId];
        return (
            proof.attestationUID,
            proof.imageHash,
            proof.timestamp,
            proof.completed
        );
    }

    // ============ Membership Management Functions ============

    /**
     * @notice Add a DAO member
     */
    function addDAOMember(address member) external onlyAdmin {
        require(member != address(0), "Invalid address");
        require(!daoMembers[member], "Already DAO member");
        daoMembers[member] = true;
        emit DAOMemberAdded(member);
    }

    /**
     * @notice Add a SubDAO member
     */
    function addSubDAOMember(address member, uint256 regionId) external onlyAdmin {
        require(member != address(0), "Invalid address");
        require(!subDaoMembers[regionId][member], "Already SubDAO member");
        subDaoMembers[regionId][member] = true;
        emit SubDAOMemberAdded(member, regionId);
    }

    // ============ Internal Helper Functions ============

    /**
     * @dev Creates a new project with the given parameters
     */
    function _createProjectInternal(
        bytes32 projectId,
        address proposer,
        string memory location,
        uint256 requestedFunds,
        uint256 regionId,
        uint256 estimatedDuration
    ) private {
        Project storage project = projects[projectId];
        project.proposer = proposer;
        project.location = location;
        project.requestedFunds = requestedFunds;
        project.regionId = regionId;
        project.estimatedDuration = estimatedDuration;
        project.isActive = true;
        project.currentPhase = 0;
    }

    /**
     * @dev Creates the initial state proof for a project
     */
    function _createInitialStateProof(
        bytes32 projectId,
        bytes32 attestationUID,
        bytes32 imageHash
    ) private {
        bytes32 stateProofId = generateStateProofId(projectId, 0);
        StateProof storage stateProof = stateProofs[stateProofId];
        stateProof.attestationUID = attestationUID;
        stateProof.imageHash = imageHash;
        stateProof.timestamp = block.timestamp;
    }

    /**
     * @dev Validates and updates state proof for a given phase
     */
    function _validateAndUpdateStateProof(
        bytes32 projectId,
        uint8 phase,
        bytes32 attestationUID,
        bytes32 imageHash
    ) private {
        require(attestationUID != bytes32(0), "Invalid attestation");
        require(imageHash != bytes32(0), "Invalid image hash");

        bytes32 stateProofId = generateStateProofId(projectId, phase + 1);
        StateProof storage stateProof = stateProofs[stateProofId];
        
        // Ensure no existing state proof
        require(stateProof.attestationUID == bytes32(0), "State proof exists");
        
        stateProof.attestationUID = attestationUID;
        stateProof.imageHash = imageHash;
        stateProof.timestamp = block.timestamp;
    }

    // ============ Utility Functions ============

    /**
     * @notice Generate a state proof ID from project ID and phase
     */
    function generateStateProofId(bytes32 projectId, uint8 phase) public pure returns (bytes32) {
        require(phase <= 2, "Invalid phase");
        return keccak256(abi.encodePacked(projectId, phase));
    }

    // ============ Fallback Functions ============

    receive() external payable {}
    fallback() external payable {}
}