// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

contract ProofOfChange {
    // Configuration
    struct VotingConfig {
        uint256 votingPeriod;      // How long voting lasts
    }

    // Stores project details like proposer, location, requested funds, region, estimated duration, start time, and status (smart contract data, not logbook entry data)
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

    // Tracks voting data from both DAO and SubDAO
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

    // Stores state proof data including attestation UID, image hash, timestamp, vote data, and completion status   
    struct StateProof {
        bytes32 attestationUID;
        bytes32 imageHash;
        uint256 timestamp;
        Vote vote;
        bool completed;
    }

    // Add this struct definition near the top of the contract with other structs
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

    // Events
    event VotingConfigUpdated(uint256 newVotingPeriod);
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
    event DAOMemberAdded(
        address indexed member
    );
    event DAOMemberRemoved(
        address indexed member
    );
    event SubDAOMemberAdded(
        address indexed member,
        uint256 indexed regionId
    );
    event SubDAOMemberRemoved(
        address indexed member,
        uint256 indexed regionId
    );

    // Storage
    mapping(bytes32 => Project) public projects;
    mapping(bytes32 => StateProof) private stateProofs;
    // Membership verification storage
    mapping(address => bool) private daoMembers;
    mapping(uint256 => mapping(address => bool)) private subDaoMembers; // regionId => member => isMember

    VotingConfig public votingConfig;
    address public admin;

    // Constructor
    constructor(uint256 initialVotingPeriod) {
        votingConfig.votingPeriod = initialVotingPeriod;
        admin = msg.sender;
    }

    // Modifiers
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
        require(
            isDAO || subDaoMembers[regionId][msg.sender],
            "Not authorized to vote"
        );
        _;
    }

    /**
     * @notice Update voting configuration
     * @param newVotingPeriod New voting period duration
     */
    function updateVotingConfig(uint256 newVotingPeriod) external onlyAdmin {
        require(newVotingPeriod > 0, "Invalid voting period");
        votingConfig.votingPeriod = newVotingPeriod;
        emit VotingConfigUpdated(newVotingPeriod);
    }

    /**
     * @notice Generate a state proof ID from project ID and phase
     * @param projectId The project ID
     * @param phase Phase number (0: Initial, 1: Progress, 2: Completion)
     */
    function generateStateProofId(bytes32 projectId, uint8 phase) public pure returns (bytes32) {
        require(phase <= 2, "Invalid phase");
        return keccak256(abi.encodePacked(projectId, phase));
    }

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
    ) external payable returns (bytes32) {
        require(msg.value == requestedFunds, "Incorrect funds sent");
        require(attestationUID != bytes32(0), "Invalid attestation");
        require(imageHash != bytes32(0), "Invalid image hash");
        require(estimatedDuration > 0, "Invalid duration");
        require(estimatedDuration <= 365 days, "Duration too long");
        
        bytes32 projectId = keccak256(abi.encodePacked(
            msg.sender,
            attestationUID,
            block.timestamp
        ));

        Project storage project = projects[projectId];
        project.proposer = msg.sender;
        project.location = location;
        project.requestedFunds = requestedFunds;
        project.regionId = regionId;
        project.estimatedDuration = estimatedDuration;
        project.isActive = true;
        project.currentPhase = 0;

        bytes32 stateProofId = generateStateProofId(projectId, 0);
        StateProof storage stateProof = stateProofs[stateProofId];
        stateProof.attestationUID = attestationUID;
        stateProof.imageHash = imageHash;
        stateProof.timestamp = block.timestamp;

        emit ProjectCreated(projectId, msg.sender, requestedFunds, estimatedDuration);

        return projectId;
    }

    /**
     * @notice Submit a new state proof for progress/completion
     * @param projectId The project ID
     * @param attestationUID New Logbook attestation
     * @param imageHash New satellite image hash
     */
    function submitStateProof(
        bytes32 projectId,
        bytes32 attestationUID,
        bytes32 imageHash
    ) external {
        Project storage project = projects[projectId];
        require(project.isActive, "Project not active");
        require(msg.sender == project.proposer, "Not proposer");
        
        uint8 currentPhase = project.currentPhase;
        require(currentPhase < 2, "Project completed");
        // ensures that the current phase is completed before allowing a new state proof submission 
        bytes32 currentStateProofId = generateStateProofId(projectId, currentPhase);
        StateProof storage currentProof = stateProofs[currentStateProofId];
        require(currentProof.completed, "Current phase not completed");
        // generates a unique ID for the new state proof by combining the project ID and the next phase number
        // checks if a state proof already exists for the new phase, reverts if state proof already exists
        bytes32 newStateProofId = generateStateProofId(projectId, currentPhase + 1);
        StateProof storage newProof = stateProofs[newStateProofId];
        require(newProof.timestamp == 0, "State proof already exists");

        newProof.attestationUID = attestationUID;
        newProof.imageHash = imageHash;
        newProof.timestamp = block.timestamp;

        emit StateProofSubmitted(projectId, currentPhase + 1, attestationUID, imageHash);
        // updates the project's current phase to the next phase
        project.currentPhase = currentPhase + 1;
    }

    /**
     * @notice Start voting period for current phase
     * @param projectId The project ID
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
     * @param projectId The project ID
     * @param support True for approval, false for rejection
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
     * @param projectId The project ID
     */
    function finalizeVoting(bytes32 projectId) external {
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

    /**
     * @notice Complete phase and release funds
     * @param projectId The project ID
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
     * @param totalFunds Total project funds
     * @param phase Current phase
     */
    function calculatePhaseAmount(uint256 totalFunds, uint8 phase) internal pure returns (uint256) {
        if (phase == 0) return totalFunds * 25 / 100; // Initial: 25%
        if (phase == 1) return totalFunds * 25 / 100; // Progress: 25%
        if (phase == 2) return totalFunds * 50 / 100; // Completion: 50%
        return 0;
    }

    /**
     * @notice Get project details including duration info
     * @param projectId The project ID
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
     * @param projectId The project ID
     * @param phase Phase number to query
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
    * @notice Get state proof details
    * @param stateProofId The state proof ID to query
    */
    function getStateProof(bytes32 stateProofId) external view returns (
        bytes32 attestationUID,
        bytes32 imageHash,
        uint256 timestamp,
        bool completed
    ) {
        StateProof storage proof = stateProofs[stateProofId];
        return (
            proof.attestationUID,
            proof.imageHash,
            proof.timestamp,
            proof.completed
        );
    }

    /**
     * @notice Get voting status for a phase
     * @param projectId The project ID
     * @param phase Phase number to query
     */
    function getVotingStatus(bytes32 projectId, uint8 phase) external view returns (
        uint256 startTime,
        uint256 endTime,
        uint256 daoFor,
        uint256 daoAgainst,
        uint256 subDaoFor,
        uint256 subDaoAgainst,
        bool finalized,
        bool approved
    ) {
        bytes32 stateProofId = generateStateProofId(projectId, phase);
        StateProof storage stateProof = stateProofs[stateProofId];
        Vote storage vote = stateProof.vote;

        return (
            vote.startTime,
            vote.startTime + votingConfig.votingPeriod,
            vote.daoFor,
            vote.daoAgainst,
            vote.subDaoFor,
            vote.subDaoAgainst,
            vote.finalized,
            vote.approved
        );
    }

   /**
     * @notice Check if address is DAO member
     * @param member Address to check
     */
    function isDAOMember(address member) public view returns (bool) {
        return daoMembers[member];
    }

    /**
     * @notice Check if address is SubDAO member for region
     * @param member Address to check
     * @param regionId Region to check membership for
     */
    function isSubDAOMember(address member, uint256 regionId) public view returns (bool) {
        return subDaoMembers[regionId][member];
    }

    /**
     * @notice Add a DAO member
     * @param member Address to add as DAO member
     */
    function addDAOMember(address member) external onlyAdmin {
        require(member != address(0), "Invalid address");
        require(!daoMembers[member], "Already DAO member");
        daoMembers[member] = true;
        emit DAOMemberAdded(member);
    }

    /**
     * @notice Add a SubDAO member
     * @param member Address to add as SubDAO member
     * @param regionId Region ID for membership
     */
    function addSubDAOMember(address member, uint256 regionId) external onlyAdmin {
        require(member != address(0), "Invalid address");
        require(!subDaoMembers[regionId][member], "Already SubDAO member");
        subDaoMembers[regionId][member] = true;
        emit SubDAOMemberAdded(member, regionId);
    }

    /**
     * @notice Remove a DAO member
     * @param member Address to remove from DAO
     */
    function removeDAOMember(address member) external onlyAdmin {
        require(daoMembers[member], "Not DAO member");
        daoMembers[member] = false;
        emit DAOMemberRemoved(member);
    }

    /**
     * @notice Remove a SubDAO member
     * @param member Address to remove from SubDAO
     * @param regionId Region ID to remove membership from
     */
    function removeSubDAOMember(address member, uint256 regionId) external onlyAdmin {
        require(subDaoMembers[regionId][member], "Not SubDAO member");
        subDaoMembers[regionId][member] = false;
        emit SubDAOMemberRemoved(member, regionId);
    }

    // TODO: batch the membership so that it adds, removes, and updates in a single gas efficient function 

    /**
     * @notice Check if member has voted on current phase
     * @param projectId The project ID
     * @param member Address to check
     */
    function hasVoted(bytes32 projectId, address member) external view returns (bool) {
        Project storage project = projects[projectId];
        bytes32 stateProofId = generateStateProofId(projectId, project.currentPhase);
        return stateProofs[stateProofId].vote.hasVoted[member];
    }

    // TODO: create a similar one to this but for proposers (in the case that the project proposer needs to be updated)
    /**
     * @notice Update admin address
     * @param newAdmin New admin address
     */
    function updateAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "Invalid address");
        admin = newAdmin;
    }
        /**
     * @notice Get contract balance
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // Function to receive Ether
    receive() external payable {}

    // Fallback function
    fallback() external payable {}

}