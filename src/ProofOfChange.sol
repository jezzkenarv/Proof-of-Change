// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "safe-smart-account/contracts/Safe.sol";
import {IProofOfChange} from "./Interfaces/IProofOfChange.sol";
import {IEAS} from "@ethereum-attestation-service/eas-contracts/contracts/IEAS.sol";
import {SchemaResolver} from "@ethereum-attestation-service/eas-contracts/contracts/SchemaResolver.sol";

// errors 
error ProofOfChangeInvalidAmount();
error ProofOfChangeEmptyImageHash();
error ProofOfChangeInvalidDuration();
error ProofOfChangeNotProposer();
error ProofOfChangeNotMainDAOmember();
error ProofOfChangeNotSubDAOmember();
error ProofOfChangeProposalNotApproved();
error ProofOfChangeProposalRejected();
error ProofOfChangeNotInProgressWindow();
error ProofOfChangeAlreadyCompleted();
error ProofOfChangeAlreadyVoted();
error ProofOfChangeVotingPeriodEnded();
error ProofOfChangeAlreadyApproved();
error ProofOfChangeProgressNotApproved();
error ProofOfChangeNotCompleted();
error ProofOfChangeNotInCompletionWindow();
error ProofOfChangeInvalidProposalId();
error ProofOfChangeNoVotingStage();
error ProofOfChangeFundsAlreadyReleased();
error ProofOfChangeFundReleaseFailed();
error ProofOfChangeEmptyTitle();
error ProofOfChangeEmptyDescription();
error ProofOfChangeInvalidAttestation();
error ProofOfChangeInvalidLocation();

contract ProofOfChange is IProofOfChange, SchemaResolver {
    uint256 public constant override COOLDOWN_PERIOD = 72 hours;

    // Change from public to private to avoid getter function conflict
    Proposal[] private _proposals;
    address private _gnosisSafe;
    mapping(address => bool) private _mainDAOMembers;
    mapping(address => bool) private _subDAOMembers;

    // Update modifiers to use private variables

    modifier onlyMainDAO() {
        if (!_mainDAOMembers[msg.sender]) revert ProofOfChangeNotMainDAOmember();
        _;
    }

    modifier onlySubDAO() {
        if (!_subDAOMembers[msg.sender]) revert ProofOfChangeNotSubDAOmember();
        _;
    }

    // Add at contract level
    uint256 private _mainDAOmemberCount;
    uint256 private _subDAOmemberCount;

    // Update the mapping to track voting stages separately
    mapping(uint256 => mapping(address => mapping(uint8 => bool))) public hasVoted;

    // Add an enum to track voting stages (add at contract level)
    enum VotingStage {
        Initial,
        Progress,
        Completion
    }

    // Change the struct to be stored in storage
    struct VotingResult {
        uint256 votesInFavor;
        uint256 votesAgainst;
        bool approved;
    }

    // Add this mapping at contract level
    mapping(uint256 => mapping(VotingStage => VotingResult)) private votingResults;

    // Add new constants
    bytes32 public constant LOCATION_SCHEMA = 0xba4171c92572b1e4f241d044c32cdf083be9fd946b8766977558ca6378c824e2;
    IEAS private immutable eas;

    constructor(
        address gnosisSafe_,
        address[] memory mainDAOMembers_,
        address[] memory subDAOMembers_,
        address easRegistry
    ) SchemaResolver(easRegistry) {
        _gnosisSafe = gnosisSafe_;
        _mainDAOmemberCount = mainDAOMembers_.length;
        _subDAOmemberCount = subDAOMembers_.length;
        for (uint256 i = 0; i < mainDAOMembers_.length; i++) {
            _mainDAOMembers[mainDAOMembers_[i]] = true;
        }
        for (uint256 i = 0; i < subDAOMembers_.length; i++) {
            _subDAOMembers[subDAOMembers_[i]] = true;
        }
        eas = IEAS(easRegistry);
    }

    // allows users to submit new proposals to the system, which can then be voted on, completed, and potentially funded

    // creates a new proposal struct and adds it to the proposals array using push
    // sets the proposer to the address of the person calling the function (msg.sender)
    // uses input params to set the startImageHash and requestedAmount
    // initializes other fields with default values

    function submitProposal(
        string memory startImageHash,
        uint256 requestedAmount,
        uint256 estimatedDays,
        string memory title,
        string memory description,
        string[] memory tags,
        string memory documentation,
        string[] memory externalLinks,
        bytes32 locationAttestationUID
    ) external returns (uint256) {
        if (requestedAmount == 0) revert ProofOfChangeInvalidAmount();
        if (bytes(startImageHash).length == 0) revert ProofOfChangeEmptyImageHash();
        if (estimatedDays == 0) revert ProofOfChangeInvalidDuration();
        if (bytes(title).length == 0) revert ProofOfChangeEmptyTitle();
        if (bytes(description).length == 0) revert ProofOfChangeEmptyDescription();

        // Validate location attestation
        IEAS.Attestation memory attestation = eas.getAttestation(locationAttestationUID);
        if (attestation.schema != LOCATION_SCHEMA) revert ProofOfChangeInvalidAttestation();
        if (!_validateLocationProof(attestation.data)) revert ProofOfChangeInvalidLocation();

        Proposal storage newProposal = _proposals.push();

        // Basic Info
        newProposal.proposer = payable(msg.sender);
        newProposal.requestedAmount = requestedAmount;
        newProposal.submissionTime = block.timestamp;
        newProposal.estimatedCompletionTime = block.timestamp + (estimatedDays * 1 days);
        newProposal.midpointTime = block.timestamp + ((estimatedDays * 1 days) / 2);

        // Metadata
        newProposal.metadata.title = title;
        newProposal.metadata.description = description;
        newProposal.metadata.tags = tags;
        newProposal.metadata.documentation = documentation;
        newProposal.metadata.externalLinks = externalLinks;

        // Set initial voting stage
        newProposal.initialVoting.startImageHash = startImageHash;

        // Initialize all voting stages
        _initializeInitialVotingStage(newProposal.initialVoting);
        _initializeProgressVotingStage(newProposal.progressVoting);
        _initializeCompletionVotingStage(newProposal.completionVoting);

        // Additional completion-specific fields
        newProposal.completionVoting.completed = false;

        // Store attestation UID
        newProposal.initialVoting.locationAttestationUID = locationAttestationUID;

        emit ProposalSubmitted(_proposals.length - 1, msg.sender, requestedAmount, startImageHash);
        emit ProposalMetadataAdded(
            _proposals.length - 1,
            title,
            description,
            tags,
            documentation,
            externalLinks
        );
        
        return _proposals.length - 1;
    }

    function _initializeInitialVotingStage(InitialVotingStage storage stage) internal {
        stage.mainDAOApproved = false;
        stage.subDAOApproved = false;
        stage.stageApproved = false;
    }

    function _initializeProgressVotingStage(ProgressVotingStage storage stage) internal {
        stage.mainDAOApproved = false;
        stage.subDAOApproved = false;
        stage.stageApproved = false;
    }

    function _initializeCompletionVotingStage(CompletionVotingStage storage stage) internal {
        stage.mainDAOApproved = false;
        stage.subDAOApproved = false;
        stage.stageApproved = false;
        stage.completed = false;
    }

    // Add a function to submit progress image
    function submitProgressImage(uint256 _proposalId, string calldata _progressImageHash) external {
        Proposal storage proposal = _getProposal(_proposalId);
        if (proposal.proposer != msg.sender) revert ProofOfChangeNotProposer();
        if (!proposal.initialVoting.stageApproved) revert ProofOfChangeProposalNotApproved();
        if (proposal.isRejected) revert ProofOfChangeProposalRejected();
        if (!isInProgressVotingWindow(_proposalId)) revert ProofOfChangeNotInProgressWindow();
        
        proposal.progressVoting.progressImageHash = _progressImageHash;
        proposal.progressVoting.votingStartTime = block.timestamp;
        
        emit ProgressImageSubmitted(_proposalId, _progressImageHash);
    }

    // allows a project proposer to mark their project as completed and submit the final image hash
    function declareProjectCompletion(uint256 _proposalId, string calldata _finalImageHash) external {
        Proposal storage proposal = _getProposal(_proposalId);
        require(proposal.proposer == msg.sender, "Only proposer can declare completion");
        require(proposal.initialVoting.stageApproved, "Proposal must be approved before completion");
        require(proposal.progressVoting.stageApproved, "Progress voting must be approved");
        require(!proposal.isRejected, "Proposal was rejected");
        require(!proposal.completionVoting.completed, "Project already marked as completed");

        proposal.completionVoting.completed = true;
        proposal.completionVoting.finalImageHash = _finalImageHash;
        proposal.completionVoting.votingStartTime = block.timestamp;

        emit ProposalCompleted(_proposalId, _finalImageHash);
    }

    // Add these internal helper functions
    function _processVote(
        uint256 proposalId,
        address voter,
        bool inFavor,
        VotingStage stage,
        uint256 requiredVotes
    ) internal {
        require(!hasVoted[proposalId][voter][uint8(stage)], "Already voted");
        hasVoted[proposalId][voter][uint8(stage)] = true;

        VotingResult storage votingResult = votingResults[proposalId][stage];

        if (inFavor) {
            votingResult.votesInFavor++;
        } else {
            votingResult.votesAgainst++;
        }

        uint256 totalVotes = votingResult.votesInFavor + votingResult.votesAgainst;
        if (totalVotes == requiredVotes) {
            votingResult.approved = (votingResult.votesInFavor > votingResult.votesAgainst);
        }
    }

    // Initial voting functions
    function voteFromMainDAO(uint256 _proposalId, bool _inFavor) external onlyMainDAO {
        Proposal storage proposal = _getProposal(_proposalId);
        require(!isVotingPeriodEnded(_proposalId), "Voting period ended");
        require(!proposal.initialVoting.mainDAOApproved, "Main DAO already approved");
        require(!proposal.isRejected, "Proposal already rejected");

        _processVote(
            _proposalId,
            msg.sender,
            _inFavor,
            VotingStage.Initial,
            _mainDAOmemberCount
        );

        // Update the proposal's voting data from our results
        VotingResult storage votingResult = votingResults[_proposalId][VotingStage.Initial];
        proposal.initialVoting.mainDAOVotesInFavor = votingResult.votesInFavor;
        proposal.initialVoting.mainDAOVotesAgainst = votingResult.votesAgainst;
        proposal.initialVoting.mainDAOApproved = votingResult.approved;

        emit MainDAOVoted(_proposalId, msg.sender, _inFavor);
    }

    function voteFromSubDAO(uint256 _proposalId, bool _inFavor) external onlySubDAO {
        Proposal storage proposal = _getProposal(_proposalId);
        require(!isVotingPeriodEnded(_proposalId), "Voting period ended");
        require(!proposal.initialVoting.subDAOApproved, "Sub DAO already approved");
        require(!proposal.isRejected, "Proposal already rejected");

        _processVote(
            _proposalId,
            msg.sender,
            _inFavor,
            VotingStage.Initial,
            _subDAOmemberCount
        );

        // Update the proposal's voting data from our results
        VotingResult storage votingResult = votingResults[_proposalId][VotingStage.Initial];
        proposal.initialVoting.subDAOVotesInFavor = votingResult.votesInFavor;
        proposal.initialVoting.subDAOVotesAgainst = votingResult.votesAgainst;
        proposal.initialVoting.subDAOApproved = votingResult.approved;

        emit SubDAOVoted(_proposalId, msg.sender, _inFavor);
    }

    // Progress voting functions
    function voteOnProgressFromMainDAO(uint256 _proposalId, bool _inFavor) external onlyMainDAO {
        Proposal storage proposal = _getProposal(_proposalId);
        require(proposal.initialVoting.stageApproved, "Initial voting must be approved first");
        require(isInProgressVotingWindow(_proposalId), "Not in progress voting window");
        require(!proposal.progressVoting.mainDAOApproved, "Main DAO already voted on progress");
        require(!proposal.isRejected, "Proposal was rejected");

        _processVote(
            _proposalId,
            msg.sender,
            _inFavor,
            VotingStage.Progress,
            _mainDAOmemberCount
        );

        // Update the proposal's voting data from our results
        VotingResult storage votingResult = votingResults[_proposalId][VotingStage.Progress];
        proposal.progressVoting.mainDAOVotesInFavor = votingResult.votesInFavor;
        proposal.progressVoting.mainDAOVotesAgainst = votingResult.votesAgainst;
        proposal.progressVoting.mainDAOApproved = votingResult.approved;

        emit MainDAOProgressVoted(_proposalId, msg.sender, _inFavor);
    }

    function voteOnProgressFromSubDAO(uint256 _proposalId, bool _inFavor) external onlySubDAO {
        Proposal storage proposal = _getProposal(_proposalId);
        require(proposal.initialVoting.stageApproved, "Initial voting must be approved first");
        require(isInProgressVotingWindow(_proposalId), "Not in progress voting window");
        require(!proposal.progressVoting.subDAOApproved, "SubDAO already voted on progress");
        require(!proposal.isRejected, "Proposal was rejected");

        _processVote(
            _proposalId,
            msg.sender,
            _inFavor,
            VotingStage.Progress,
            _subDAOmemberCount
        );

        // Update the proposal's voting data from our results
        VotingResult storage votingResult = votingResults[_proposalId][VotingStage.Progress];
        proposal.progressVoting.subDAOVotesInFavor = votingResult.votesInFavor;
        proposal.progressVoting.subDAOVotesAgainst = votingResult.votesAgainst;
        proposal.progressVoting.subDAOApproved = votingResult.approved;

        emit SubDAOProgressVoted(_proposalId, msg.sender, _inFavor);
    }

    // Completion voting functions
    function voteOnCompletionFromMainDAO(uint256 _proposalId, bool _inFavor) external onlyMainDAO {
        Proposal storage proposal = _getProposal(_proposalId);
        require(proposal.progressVoting.stageApproved, "Progress voting must be approved first");
        require(proposal.completionVoting.completed, "Project must be marked as completed first");
        require(isInCompletionVotingWindow(_proposalId), "Not in completion voting window");
        require(!proposal.completionVoting.mainDAOApproved, "Main DAO already voted on completion");

        _processVote(
            _proposalId,
            msg.sender,
            _inFavor,
            VotingStage.Completion,
            _mainDAOmemberCount
        );

        // Update the proposal's voting data from our results
        VotingResult storage votingResult = votingResults[_proposalId][VotingStage.Completion];
        proposal.completionVoting.mainDAOVotesInFavor = votingResult.votesInFavor;
        proposal.completionVoting.mainDAOVotesAgainst = votingResult.votesAgainst;
        proposal.completionVoting.mainDAOApproved = votingResult.approved;

        emit MainDAOCompletionVoted(_proposalId, msg.sender, _inFavor);
    }

    function voteOnCompletionFromSubDAO(uint256 _proposalId, bool _inFavor) external onlySubDAO {
        Proposal storage proposal = _getProposal(_proposalId);
        require(proposal.progressVoting.stageApproved, "Progress voting must be approved first");
        require(proposal.completionVoting.completed, "Project must be marked as completed first");
        require(isInCompletionVotingWindow(_proposalId), "Not in completion voting window");
        require(!proposal.completionVoting.subDAOApproved, "SubDAO already voted on completion");

        _processVote(
            _proposalId,
            msg.sender,
            _inFavor,
            VotingStage.Completion,
            _subDAOmemberCount
        );

        // Update the proposal's voting data from our results
        VotingResult storage votingResult = votingResults[_proposalId][VotingStage.Completion];
        proposal.completionVoting.subDAOVotesInFavor = votingResult.votesInFavor;
        proposal.completionVoting.subDAOVotesAgainst = votingResult.votesAgainst;
        proposal.completionVoting.subDAOApproved = votingResult.approved;

        emit SubDAOCompletionVoted(_proposalId, msg.sender, _inFavor);
    }

    // Add function to finalize voting
    /////////////////////////////////////// move each stage into separate function

    function finalizeVoting(uint256 _proposalId) external {
        Proposal storage proposal = _getProposal(_proposalId);
        
        // Initial voting stage
        if (!proposal.initialVoting.stageApproved && !proposal.isRejected) {
            require(block.timestamp >= proposal.submissionTime + COOLDOWN_PERIOD, "Initial voting period not ended");
            
            bool mainDAOApproved = proposal.initialVoting.mainDAOVotesInFavor > proposal.initialVoting.mainDAOVotesAgainst;
            bool subDAOApproved = proposal.initialVoting.subDAOVotesInFavor > proposal.initialVoting.subDAOVotesAgainst;
            
            if (mainDAOApproved && subDAOApproved) {
                proposal.initialVoting.stageApproved = true;
            } else {
                proposal.isRejected = true;
            }
            
            emit ProposalFinalized(_proposalId, proposal.initialVoting.stageApproved);
            return;
        }

        // Progress voting stage
        if (proposal.initialVoting.stageApproved && !proposal.progressVoting.stageApproved) {
            require(block.timestamp >= proposal.midpointTime + COOLDOWN_PERIOD, "Progress voting period not ended");
            
            bool mainDAOApproved = proposal.progressVoting.mainDAOVotesInFavor > proposal.progressVoting.mainDAOVotesAgainst;
            bool subDAOApproved = proposal.progressVoting.subDAOVotesInFavor > proposal.progressVoting.subDAOVotesAgainst;
            
            if (mainDAOApproved && subDAOApproved) {
                proposal.progressVoting.stageApproved = true;
            } else {
                proposal.isRejected = true;
            }
            
            emit ProposalProgressFinalized(_proposalId, proposal.progressVoting.stageApproved);
            return;
        }

        // Completion voting stage
        if (proposal.progressVoting.stageApproved && !proposal.completionVoting.stageApproved && proposal.completionVoting.completed) {
            require(block.timestamp >= proposal.completionVoting.votingStartTime + COOLDOWN_PERIOD, "Completion voting period not ended");
            
            bool mainDAOApproved = proposal.completionVoting.mainDAOVotesInFavor > proposal.completionVoting.mainDAOVotesAgainst;
            bool subDAOApproved = proposal.completionVoting.subDAOVotesInFavor > proposal.completionVoting.subDAOVotesAgainst;
            
            if (mainDAOApproved && subDAOApproved) {
                proposal.completionVoting.stageApproved = true;
            } else {
                proposal.isRejected = true;
            }
            
            emit ProposalCompletionFinalized(_proposalId, proposal.completionVoting.stageApproved);
            return;
        }

        revert("No voting stage to finalize");
    }

    // Releases the funds to a project proposer after their proposal has been approved and completed
    function releaseFunds(uint256 _proposalId) external {
        Proposal storage proposal = _getProposal(_proposalId);
        require(proposal.initialVoting.stageApproved, "Proposal not approved");
        require(!proposal.isRejected, "Proposal was rejected");
        require(proposal.completionVoting.completed, "Project must be completed");
        require(!proposal.fundsReleased, "Funds already released");
        require(
            proposal.completionVoting.mainDAOApproved && proposal.completionVoting.subDAOApproved,
            "Both Main DAO and SubDAO must approve completion"
        );

        proposal.fundsReleased = true;

        // Execute fund release via Safe
        bool success = Safe(payable(_gnosisSafe)).execTransactionFromModule(
            proposal.proposer,
            proposal.requestedAmount,
            "", // indicates no additional data is sent with the transaction
            Enum.Operation.Call
        );
        require(success, "Fund release transaction failed");

        emit FundsReleased(_proposalId, proposal.proposer, proposal.requestedAmount);
    }

    // Add function to check if voting period has ended
    function isVotingPeriodEnded(uint256 _proposalId) public view returns (bool) {
        Proposal storage proposal = _getProposal(_proposalId);
        return block.timestamp >= proposal.submissionTime + COOLDOWN_PERIOD;
    }

    // External wrapper functions
    function isInProgressVotingWindow(uint256 _proposalId) public view returns (bool) {
        Proposal storage proposal = _getProposal(_proposalId);
        uint256 windowBuffer = 3 days;
        return block.timestamp >= proposal.midpointTime - windowBuffer
            && block.timestamp <= proposal.midpointTime + windowBuffer;
    }

    function isInCompletionVotingWindow(uint256 _proposalId) public view returns (bool) {
        Proposal storage proposal = _getProposal(_proposalId);
        uint256 windowBuffer = 3 days;
        return block.timestamp >= proposal.estimatedCompletionTime - windowBuffer
            && block.timestamp <= proposal.estimatedCompletionTime + windowBuffer;
    }

    // Add getter functions to match interface
    function proposals(uint256 index) external view override returns (Proposal memory) {
        return _proposals[index];
    }

    function gnosisSafe() external view override returns (address) {
        return _gnosisSafe;
    }

    function mainDAOMembers(address member) external view override returns (bool) {
        return _mainDAOMembers[member];
    }

    function subDAOMembers(address member) external view override returns (bool) {
        return _subDAOMembers[member];
    }

    function _getProposal(uint256 _proposalId) internal view returns (Proposal storage) {
        if (_proposalId >= _proposals.length) revert ProofOfChangeInvalidProposalId();
        return _proposals[_proposalId];
    }

    // Add validation functions
    function _validateLocationProof(bytes memory data) internal pure returns (bool) {
        // Decode attestation data
        (
            uint256 eventTimestamp,
            string memory srs,
            string memory locationType,
            string memory location,
            string[] memory mediaTypes,
            string[] memory mediaData,
            string[] memory recipeTypes,
            bytes[] memory recipePayload,
            string memory memo
        ) = abi.decode(
            data,
            (uint256, string, string, string, string[], string[], string[], bytes[], string)
        );
        
        // Validate SRS is EPSG:4326
        if (keccak256(bytes(srs)) != keccak256(bytes("EPSG:4326"))) {
            return false;
        }
        
        // Validate location type
        if (keccak256(bytes(locationType)) != keccak256(bytes("DecimalDegrees<string>"))) {
            return false;
        }
        
        // Ensure required media exists
        if (mediaTypes.length == 0 || mediaData.length == 0) {
            return false;
        }
        
        return true;
    }

    // Implement SchemaResolver's isValid function
    function isValid(
        bytes32 attestationUID,
        address attester,
        bytes memory data
    ) external view override returns (bool) {
        return _validateLocationProof(data);
    }
}
