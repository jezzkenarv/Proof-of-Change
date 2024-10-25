// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "node_modules/@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";

contract RetroFund is PluginUUPSUpgradeable, ReentrancyGuard {
    struct Proposal {
        address payable proposer;
        string startImageHash;
        uint256 requestedAmount;
        bool approved;
        bool completed;
        bool fundsReleased;
        string finalImageHash;
        uint256 votesInFavor;
        uint256 votesAgainst;
        uint256 completionVotesInFavor;
        uint256 completionVotesAgainst;
        bool completionApproved;
    }

    // State variables
    Proposal[] public proposals;
    uint256 public constant VOTE_THRESHOLD = 5;

    // Events
    event ProposalSubmitted(uint256 proposalId, address proposer, uint256 amount, string startImageHash);
    event ProposalVoted(uint256 proposalId, address voter, bool inFavor);
    event ProposalCompleted(uint256 proposalId, string finalImageHash);
    event FundsReleased(uint256 proposalId, address proposer, uint256 amount);
    event CompletionVoted(uint256 proposalId, address voter, bool inFavor);
    event CompletionApproved(uint256 proposalId);

    // Permission IDs
    bytes32 public constant SUBMIT_PROPOSAL_ROLE = keccak256("SUBMIT_PROPOSAL_ROLE");
    bytes32 public constant VOTE_ROLE = keccak256("VOTE_ROLE");
    bytes32 public constant RELEASE_ROLE = keccak256("RELEASE_ROLE");
    bytes32 public constant TRUSTED_COMMITTEE_ROLE = keccak256("TRUSTED_COMMITTEE_ROLE");

    function initialize(IDAO _dao) external initializer {
        __PluginUUPSUpgradeable_init(_dao);
    }

    function submitProposal(
        string calldata _startImageHash,
        uint256 _requestedAmount
    ) external auth(SUBMIT_PROPOSAL_ROLE) nonReentrant {
        proposals.push(Proposal({
            proposer: payable(msg.sender),
            startImageHash: _startImageHash,
            requestedAmount: _requestedAmount,
            approved: false,
            completed: false,
            fundsReleased: false,
            finalImageHash: "",
            votesInFavor: 0,
            votesAgainst: 0,
            completionVotesInFavor: 0,
            completionVotesAgainst: 0,
            completionApproved: false
        }));
        
        emit ProposalSubmitted(proposals.length - 1, msg.sender, _requestedAmount, _startImageHash);
    }

    function voteOnProposal(
        uint256 _proposalId,
        bool _inFavor
    ) external auth(VOTE_ROLE) auth(TRUSTED_COMMITTEE_ROLE) nonReentrant {
        Proposal storage proposal = proposals[_proposalId];
        require(!proposal.approved, "Proposal already approved");

        if (_inFavor) {
            proposal.votesInFavor++;
        } else {
            proposal.votesAgainst++;
        }

        uint256 totalVotes = proposal.votesInFavor + proposal.votesAgainst;
        if (proposal.votesInFavor > proposal.votesAgainst && totalVotes > VOTE_THRESHOLD) {
            proposal.approved = true;
        }

        emit ProposalVoted(_proposalId, msg.sender, _inFavor);
    }

    function declareProjectCompletion(
        uint256 _proposalId,
        string calldata _finalImageHash
    ) external nonReentrant {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.proposer == msg.sender, "Only proposer can declare completion");
        require(proposal.approved, "Proposal must be approved");
        require(!proposal.completed, "Project already completed");

        proposal.completed = true;
        proposal.finalImageHash = _finalImageHash;

        emit ProposalCompleted(_proposalId, _finalImageHash);
    }

    function voteOnCompletion(
        uint256 _proposalId,
        bool _inFavor
    ) external auth(VOTE_ROLE) auth(TRUSTED_COMMITTEE_ROLE) nonReentrant {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.completed, "Project must be completed first");
        require(!proposal.completionApproved, "Completion already approved");

        if (_inFavor) {
            proposal.completionVotesInFavor++;
        } else {
            proposal.completionVotesAgainst++;
        }

        if (proposal.completionVotesInFavor > proposal.completionVotesAgainst) {
            proposal.completionApproved = true;
            emit CompletionApproved(_proposalId);
        }

        emit CompletionVoted(_proposalId, msg.sender, _inFavor);
    }

    function releaseFunds(
        uint256 _proposalId
    ) external auth(RELEASE_ROLE) auth(TRUSTED_COMMITTEE_ROLE) nonReentrant {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.completed, "Project must be completed");
        require(!proposal.fundsReleased, "Funds already released");
        require(proposal.completionApproved, "Completion must be approved");
        
        proposal.fundsReleased = true;

        // Transfer funds using Aragon DAO's execute function
        bytes memory data = abi.encodeWithSignature(
            "transfer(address,uint256)",
            proposal.proposer,
            proposal.requestedAmount
        );

        dao().execute({
            _target: dao().getTokenContract(),
            _value: 0,
            _data: data
        });

        emit FundsReleased(_proposalId, proposal.proposer, proposal.requestedAmount);
    }
}