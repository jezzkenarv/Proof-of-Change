// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// This contract is for testing purposes and simulates an attestation system where users can create and verify claims

contract MockEAS {
    // ============ Internal Structs ============
    
    struct Attestation {
        bytes32 uid;          // Unique identifier of the attestation
        bytes32 schema;       // Schema of the attestation
        address attester;     // Address of the attester
        address recipient;    // Address of the recipient
        uint64 time;         // Time when the attestation was created
        uint64 revocationTime; // Time when the attestation was revoked (0 if not revoked)
        uint64 expirationTime; // Time when the attestation expires (0 if no expiration)
        bool revocable;      // Whether the attestation is revocable
        bytes32 refUID;      // Reference to another attestation (0 if no reference)
        bytes data;          // Custom attestation data
    }

    struct AttestationRequest {
        bytes32 schema;
        address recipient;
        uint64 expirationTime;
        bool revocable;
        bytes32 refUID;
        bytes data;
        uint256 value;
    }

    // ============ Storage ============

    mapping(bytes32 => Attestation) public attestations;
    bytes32 public constant SCHEMA = bytes32(uint256(1)); // Mock schema ID

    // ============ Events ============ 

    event Attested(
        bytes32 indexed uid,
        bytes32 indexed schema,
        address indexed attester,
        bytes data
    );
    
    // ============ Functions ============

    /**
     * @dev Creates a new attestation
     * @param request The attestation request
     * @return uid The unique identifier of the attestation
     */
    function attest(AttestationRequest calldata request) external payable returns (bytes32) {
        bytes32 uid = _generateUID(msg.sender, request.data);
        
        attestations[uid] = Attestation({
            uid: uid,
            schema: request.schema,
            attester: msg.sender,
            recipient: request.recipient,
            time: uint64(block.timestamp),
            revocationTime: 0,
            expirationTime: request.expirationTime,
            revocable: request.revocable,
            refUID: request.refUID,
            data: request.data
        });

        emit Attested(uid, request.schema, msg.sender, request.data);
        return uid;
    }

    /**
     * @dev Gets an attestation by its UID
     * @param uid The unique identifier of the attestation
     * @return The attestation
     */
    function getAttestation(bytes32 uid) external view returns (Attestation memory) {
        return attestations[uid];
    }

    /**
     * @dev Generates a unique identifier for an attestation
     * @param attester The address of the attester
     * @param data The attestation data
     * @return The unique identifier
     */
    function _generateUID(address attester, bytes memory data) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            block.timestamp,
            attester,
            data
        ));
    }

    /**
     * @dev Creates a mock attestation for testing
     * @param creator The address to be set as the attester
     * @param refUID Reference to another attestation (optional)
     * @return The unique identifier of the created attestation
     */
    function createMockAttestation(
        address creator,
        bytes32 refUID
    ) external returns (bytes32) {
        bytes memory mockData = abi.encode(
            uint256(block.timestamp),
            "Mock Location",
            "Mock Description"
        );

        bytes32 uid = _generateUID(creator, mockData);

        attestations[uid] = Attestation({
            uid: uid,
            schema: SCHEMA,
            attester: creator,
            recipient: creator,
            time: uint64(block.timestamp),
            revocationTime: 0,
            expirationTime: 0,
            revocable: true,
            refUID: refUID,
            data: mockData
        });

        emit Attested(uid, SCHEMA, creator, mockData);
        return uid;
    }
} 