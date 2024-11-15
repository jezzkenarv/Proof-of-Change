// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @title IProofOfChange
 * @dev Interface for the ProofOfChange contract
 */
interface IProofOfChange {
    // ============ Custom Errors ============
    error OnlyAdmin();
    error OnlyDAOMember();
    error OnlySubDAOMember();
    error NotAuthorizedToVote();
    error InvalidAddress();
    error InvalidDuration();
    error InvalidPhase();
    error InvalidAttestation();
    error InvalidImageHash();
    error IncorrectFundsSent();
    error ProjectNotActive();
    error NotProposer();
    error ProjectCompleted();
    error StateProofExists();
    error NoAttestation();
    error VotingNotStarted();
    error VotingAlreadyStarted();
    error VotingEnded();
    error VotingPeriodNotEnded();
    error AlreadyVoted();
    error VotingPeriodEnded();
    error AlreadyFinalized();
    error FundTransferFailed();
    error AlreadyDAOMember();
    error AlreadySubDAOMember();
    error NotDAOMember();
    error NotSubDAOMember();

    // ============ Structs ============
    
    struct VotingConfig {
        uint256 votingPeriod;
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
    event AdminUpdated(address indexed newAdmin);
    
    event ProjectCreated(
        bytes32 indexed projectId,
        address indexed proposer,
        uint256 requestedFunds,
        uint256 estimatedDuration
    );
    
    event StateProofSubmitted(
        bytes32 indexed projectId,
        uint8 indexed phase,
        bytes32 attestationUID,
        bytes32 imageHash
    );
    
    event VoteCast(
        bytes32 indexed projectId,
        uint8 indexed phase,
        address indexed voter,
        bool isDAO,
        bool support
    );
    
    event VotingStarted(
        bytes32 indexed projectId,
        uint8 indexed phase,
        uint256 startTime,
        uint256 endTime
    );
    
    event VotingCompleted(
        bytes32 indexed projectId,
        uint8 indexed phase,
        bool approved
    );
    
    event PhaseCompleted(
        bytes32 indexed projectId,
        uint8 indexed phase,
        uint256 timestamp
    );
    
    event FundsReleased(
        bytes32 indexed projectId,
        uint8 indexed phase,
        uint256 amount
    );
    
    event DAOMemberAdded(address indexed member);
    event DAOMemberRemoved(address indexed member);
    
    event SubDAOMemberAdded(
        address indexed member,
        uint256 indexed regionId
    );
    
    event SubDAOMemberRemoved(
        address indexed member,
        uint256 indexed regionId
    );

    // ============ External Functions ============

    /**
     * @notice Create initial project and state proof
     * @param attestationUID Initial Logbook attestation
     * @param imageHash Initial satellite image hash
     * @param location Project location
     * @param requestedFunds Amount of funds requested
     * @param regionId Geographic region ID
     * @param estimatedDuration Estimated project duration in seconds
     * @return projectId The unique identifier for the created project
     */
    function createProject(
        bytes32 attestationUID,
        bytes32 imageHash,
        string calldata location,
        uint256 requestedFunds,
        uint256 regionId,
        uint256 estimatedDuration
    ) external payable returns (bytes32);

    /**
     * @notice Submit a new state proof for progress/completion
     */
    function submitStateProof(
        bytes32 projectId,
        bytes32 attestationUID,
        bytes32 imageHash
    ) external;

    /**
     * @notice Start voting period for current phase
     */
    function startVoting(bytes32 projectId) external;

    /**
     * @notice Cast vote for current phase
     */
    function castVote(bytes32 projectId, bool support) external;

    /**
     * @notice Finalize voting and process results
     */
    function finalizeVoting(bytes32 projectId) external;

    /**
     * @notice Get project details including duration info
     */
    function getProjectDetails(bytes32 projectId) external view returns (ProjectDetails memory);

    /**
     * @notice Get state proof details
     */
    function getStateProofDetails(bytes32 projectId, uint8 phase) external view returns (
        bytes32 attestationUID,
        bytes32 imageHash,
        uint256 timestamp,
        bool completed
    );

    /**
     * @notice Add a DAO member
     */
    function addDAOMember(address member) external;

    /**
     * @notice Add a SubDAO member
     */
    function addSubDAOMember(address member, uint256 regionId) external;

    /**
     * @notice Remove a DAO member
     */
    function removeDAOMember(address member) external;

    /**
     * @notice Remove a SubDAO member
     */
    function removeSubDAOMember(address member, uint256 regionId) external;

    /**
     * @notice Update voting configuration
     */
    function updateVotingConfig(uint256 newVotingPeriod) external;

    /**
     * @notice Generate a state proof ID from project ID and phase
     */
    function generateStateProofId(bytes32 projectId, uint8 phase) external pure returns (bytes32);

    /**
     * @notice Check if address is DAO member
     */
    function isDAOMember(address member) external view returns (bool);

    /**
     * @notice Check if address is SubDAO member for region
     */
    function isSubDAOMember(address member, uint256 regionId) external view returns (bool);

    /**
     * @notice Check if member has voted on current phase
     */
    function hasVoted(bytes32 projectId, address member) external view returns (bool);

    /**
     * @notice Update admin address
     */
    function updateAdmin(address newAdmin) external;

    /**
     * @notice Get contract balance
     */
    function getContractBalance() external view returns (uint256);
}
