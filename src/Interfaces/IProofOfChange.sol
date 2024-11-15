// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @title IProofOfChange
 * @dev Interface for the ProofOfChange contract
 */
interface IProofOfChange {
    /**
     * @dev Emitted when voting configuration is updated
     */
    event VotingConfigUpdated(uint256 newVotingPeriod);
    
    /**
     * @dev Emitted when a new project is created
     */
    event ProjectCreated(
        bytes32 indexed projectId,
        address indexed proposer,
        uint256 requestedFunds,
        uint256 estimatedDuration
    );

    // ... other events ...

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

    // ... other external function declarations ...
}
