// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@eas/IEAS.sol";
import "@eas/resolver/SchemaResolver.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./interfaces/IProofOfChange.sol";

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
contract ProofOfChange is IProofOfChange, ReentrancyGuard {

    // ============ Internal Structs ============
    // These structs are not exposed in the interface because they're only used internally
    
    struct Project {
        address proposer;
        string location;           
        uint256 requestedFunds;
        uint256 regionId;
        uint256 estimatedDuration; // Duration in seconds
        uint256 startTime;         // When project begins (after initial phase approval)
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
        if (msg.sender != admin) revert OnlyAdmin();
        _;
    }

    modifier onlyDAOMember() {
        if (!daoMembers[msg.sender]) revert OnlyDAOMember();
        _;
    }

    modifier onlySubDAOMember(uint256 regionId) {
        if (!subDaoMembers[regionId][msg.sender]) revert OnlySubDAOMember();
        _;
    }

    modifier onlyDAOOrSubDAOMember(uint256 regionId) {
        bool isDAO = daoMembers[msg.sender];
        if (!isDAO && !subDaoMembers[regionId][msg.sender]) revert NotAuthorizedToVote();
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
        if (msg.value != requestedFunds) revert IncorrectFundsSent();
        if (attestationUID == bytes32(0)) revert InvalidAttestation();
        if (imageHash == bytes32(0)) revert InvalidImageHash();
        if (estimatedDuration == 0 || estimatedDuration > 365 days) revert InvalidDuration();
        
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
        if (!project.isActive) revert ProjectNotActive();
        if (msg.sender != project.proposer) revert NotProposer();
        
        uint8 currentPhase = project.currentPhase;
        if (currentPhase >= 2) revert ProjectCompleted();
        
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
        if (!project.isActive) revert ProjectNotActive();
        if (msg.sender != project.proposer) revert NotProposer();

        bytes32 stateProofId = generateStateProofId(projectId, project.currentPhase);
        StateProof storage stateProof = stateProofs[stateProofId];
        
        if (stateProof.attestationUID == bytes32(0)) revert NoAttestation();
        if (stateProof.vote.startTime != 0) revert VotingAlreadyStarted();
        if (project.currentPhase > 2) revert ProjectCompleted();

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
        if (!project.isActive) revert ProjectNotActive();

        bytes32 stateProofId = generateStateProofId(projectId, project.currentPhase);
        StateProof storage stateProof = stateProofs[stateProofId];
        Vote storage vote = stateProof.vote;

        if (vote.startTime == 0) revert VotingNotStarted();
        if (vote.finalized) revert VotingEnded();
        if (vote.hasVoted[msg.sender]) revert AlreadyVoted();
        if (block.timestamp > vote.startTime + votingConfig.votingPeriod) revert VotingPeriodEnded();

        if (isDAO) {
            if (support) vote.daoFor++; 
            else vote.daoAgainst++;
        } else {
            if (support) vote.subDaoFor++; 
            else vote.subDaoAgainst++;
        }

        vote.hasVoted[msg.sender] = true;
        emit VoteCast(projectId, project.currentPhase, msg.sender, isDAO, support);
    }

    /**
     * @notice Finalize voting and process results
     */
    function finalizeVoting(bytes32 projectId) external nonReentrant {
        Project storage project = projects[projectId];
        if (!project.isActive) revert ProjectNotActive();

        bytes32 stateProofId = generateStateProofId(projectId, project.currentPhase);
        StateProof storage stateProof = stateProofs[stateProofId];
        Vote storage vote = stateProof.vote;

        if (vote.startTime == 0) revert VotingNotStarted();
        if (vote.finalized) revert AlreadyFinalized();
        if (block.timestamp <= vote.startTime + votingConfig.votingPeriod) revert VotingPeriodNotEnded();

        bool daoApproved = vote.daoFor > vote.daoAgainst;
        bool subDaoApproved = vote.subDaoFor > vote.subDaoAgainst;

        vote.finalized = true;
        vote.approved = daoApproved && subDaoApproved;

        emit VotingCompleted(projectId, project.currentPhase, vote.approved);

        if (vote.approved) {
            completePhase(projectId);
            if (project.currentPhase == 2) {
                project.isActive = false;
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

    /**
     * @notice Check if an address is a DAO member
     */
    function isDAOMember(address member) external view returns (bool) {
        return daoMembers[member];
    }

    /**
     * @notice Check if an address is a SubDAO member for a specific region
     */
    function isSubDAOMember(address member, uint256 regionId) external view returns (bool) {
        return subDaoMembers[regionId][member];
    }

    /**
     * @notice Check if a member has voted on a project's current phase
     */
    function hasVoted(bytes32 projectId, address member) external view returns (bool) {
        bytes32 stateProofId = generateStateProofId(projectId, projects[projectId].currentPhase);
        return stateProofs[stateProofId].vote.hasVoted[member];
    }

    /**
     * @notice Get the current contract balance
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // ============ Membership Management Functions ============

    /**
     * @notice Add a DAO member
     */
    function addDAOMember(address member) external onlyAdmin {
        if (member == address(0)) revert InvalidAddress();
        if (daoMembers[member]) revert AlreadyDAOMember();
        daoMembers[member] = true;
        emit DAOMemberAdded(member);
    }

    /**
     * @notice Add a SubDAO member
     */
    function addSubDAOMember(address member, uint256 regionId) external onlyAdmin {
        if (member == address(0)) revert InvalidAddress();
        if (subDaoMembers[regionId][member]) revert AlreadySubDAOMember();
        subDaoMembers[regionId][member] = true;
        emit SubDAOMemberAdded(member, regionId);
    }

    function removeDAOMember(address member) external onlyAdmin {
        if (!daoMembers[member]) revert NotDAOMember();
        daoMembers[member] = false;
        emit DAOMemberRemoved(member);
    }

    function removeSubDAOMember(address member, uint256 regionId) external onlyAdmin {
        if (!subDaoMembers[regionId][member]) revert NotSubDAOMember();
        subDaoMembers[regionId][member] = false;
        emit SubDAOMemberRemoved(member, regionId);
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
        if (phase > 2) revert InvalidPhase();
        return keccak256(abi.encodePacked(projectId, phase));
    }

    // ============ Fallback Functions ============

    receive() external payable {}
    fallback() external payable {}

    // ============ Admin Functions ============

    /**
     * @notice Update the voting period configuration
     */
    function updateVotingConfig(uint256 newVotingPeriod) external onlyAdmin {
        votingConfig.votingPeriod = newVotingPeriod;
        emit VotingConfigUpdated(newVotingPeriod);
    }

    /**
     * @notice Update the admin address
     */
    function updateAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert InvalidAddress();
        admin = newAdmin;
        emit AdminUpdated(newAdmin);
    }
}