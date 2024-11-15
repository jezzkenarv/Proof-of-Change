// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, Vm} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {ProofOfChange} from "../../src/ProofOfChange.sol";
import {IProofOfChange} from "../../src/Interfaces/IProofOfChange.sol";
import {IEAS, AttestationRequest, AttestationRequestData, Attestation} from "@eas/IEAS.sol";

// Define minimal interfaces needed for testing
// interface IMinimalEAS {
//     function attest(AttestationRequest calldata request) external payable returns (bytes32);
//     function getAttestation(bytes32 uid) external view returns (Attestation memory);
// }

// contract MockEAS is IMinimalEAS {
//     mapping(bytes32 => Attestation) public attestations;
//     bytes32 public constant LOGBOOK_SCHEMA = 0xb16fa048b0d597f5a821747eba64efa4762ee5143e9a80600d0005386edfc995;

//     // Add helper function for direct attestation creation
//     function createMockAttestation(address creator, bytes32 logbookUID) external returns (bytes32) {
//         bytes memory mockData = abi.encode(
//             uint256(block.timestamp),
//             "Mock Location",
//             "Mock Description"
//         );

//         bytes32 uid = keccak256(abi.encodePacked(
//             block.timestamp,
//             creator,
//             mockData
//         ));

//         attestations[uid] = Attestation({
//             uid: uid,
//             schema: LOGBOOK_SCHEMA,
//             attester: creator,
//             recipient: creator,
//             time: uint64(block.timestamp),
//             revocationTime: 0,
//             expirationTime: type(uint64).max,
//             revocable: true,
//             refUID: logbookUID,
//             data: mockData
//         });

//         return uid;
//     }

//     function attest(AttestationRequest calldata request) external payable returns (bytes32) {
//         bytes32 uid = keccak256(abi.encodePacked(
//             block.timestamp,
//             msg.sender,
//             request.data.data
//         ));

//         attestations[uid] = Attestation({
//             uid: uid,
//             schema: request.schema,
//             attester: msg.sender,
//             recipient: request.data.recipient,
//             time: uint64(block.timestamp),
//             revocationTime: 0,
//             expirationTime: request.data.expirationTime,
//             revocable: request.data.revocable,
//             refUID: request.data.refUID,
//             data: request.data.data
//         });

//         return uid;
//     }

//     function getAttestation(bytes32 uid) external view returns (Attestation memory) {
//         Attestation memory att = attestations[uid];
//         require(att.attester != address(0), "Attestation not found");
//         return att;
//     }
// }


 contract ProofOfChangeTest is Test {
//     ProofOfChange public poc;
//     MockEAS public mockEAS;
    
//     address public constant ADMIN = address(1);
//     address public constant USER = address(2);
//     address public constant SUBDAO_MEMBER = address(3);
    
//     uint256 public constant INITIAL_FUNDS = 1 ether;
    
//     event ProjectCreated(
//         bytes32 indexed projectId,
//         address indexed proposer,
//         uint256 requestedFunds,
//         uint256 duration,
//         bytes32 logbookAttestationUID
//     );

//     function setUp() public {
//         // Deploy mock EAS
//         mockEAS = new MockEAS();
        
//         // Create initial DAO members array
//         address[] memory initialMembers = new address[](1);
//         initialMembers[0] = ADMIN;
        
//         // Deploy ProofOfChange
//         poc = new ProofOfChange(address(mockEAS), initialMembers);
        
//         // Setup test accounts
//         vm.deal(USER, 10 ether);
        
//         // Add SubDAO member (must be called by ADMIN)
//         vm.prank(ADMIN);
//         poc.addSubDAOMember(SUBDAO_MEMBER, 1); // Add to region 1
//     }

//     /*//////////////////////////////////////////////////////////////
//                         PROJECT CREATION TESTS
//     //////////////////////////////////////////////////////////////*/

//     function testCreateProject() public {
//         // Set a specific timestamp for consistency
//         vm.warp(1000);

//         // Create initial attestation
//         bytes32 attestationUID = _createMockAttestation();
        
//         // Verify the attestation was created correctly
//         Attestation memory att = mockEAS.getAttestation(attestationUID);
//         assertEq(att.attester, USER, "Wrong attester");
//         assertEq(att.time, uint64(block.timestamp), "Wrong timestamp");
//         assertEq(att.revocationTime, 0, "Wrong revocation time");
//         assertEq(att.revocable, true, "Wrong revocable status");
        
//         // Create project data
//         IProofOfChange.ProjectCreationData memory data = IProofOfChange.ProjectCreationData({
//             regionId: 1,
//             requestedFunds: INITIAL_FUNDS,
//             duration: 30 days,
//             logbookAttestationUID: attestationUID
//         });
        
//         // Create project and capture the event
//         vm.recordLogs();
        
//         vm.prank(USER);
//         bytes32 projectId = poc.createProject{value: INITIAL_FUNDS}(data);
        
//         // Get the emitted event
//         Vm.Log[] memory entries = vm.getRecordedLogs();
        
//         // Verify event data
//         assertEq(entries.length > 0, true, "No events emitted");
//         assertEq(entries[0].topics[0], keccak256("ProjectCreated(bytes32,address,uint256,uint256,bytes32)"));
//         assertEq(entries[0].topics[1], bytes32(projectId)); // project ID
//         assertEq(entries[0].topics[2], bytes32(uint256(uint160(USER)))); // proposer address
        
//         // Decode the non-indexed parameters
//         (uint256 requestedFunds, uint256 duration, bytes32 logbookUID) = 
//             abi.decode(entries[0].data, (uint256, uint256, bytes32));
            
//         assertEq(requestedFunds, INITIAL_FUNDS);
//         assertEq(duration, 30 days);
//         assertEq(logbookUID, attestationUID);
        
//         // Verify project details
//         (
//             address proposer,
//             uint256 storedFunds,
//             uint256 storedDuration,
//             IProofOfChange.VoteType currentPhase,
//             bytes32[] memory attestationUIDs
//         ) = poc.getProjectDetails(projectId);
        
//         assertEq(proposer, USER);
//         assertEq(storedFunds, INITIAL_FUNDS);
//         assertEq(storedDuration, 30 days);
//         assertEq(uint256(currentPhase), uint256(IProofOfChange.VoteType.Initial));
//         assertEq(attestationUIDs[0], attestationUID);
//     }

//     function testCannotCreateProjectWithoutFunds() public {
//         bytes32 attestationUID = _createMockAttestation();
        
//         IProofOfChange.ProjectCreationData memory data = IProofOfChange.ProjectCreationData({
//             regionId: 1,
//             requestedFunds: INITIAL_FUNDS,
//             duration: 30 days,
//             logbookAttestationUID: attestationUID
//         });
        
//         vm.prank(USER);
//         vm.expectRevert("Incorrect funds");
//         poc.createProject(data);
//     }

//     /*//////////////////////////////////////////////////////////////
//                             VOTING TESTS
//     //////////////////////////////////////////////////////////////*/

//     function testVoting() public {
//         bytes32 projectId = _createTestProject();
//         bytes32 attestationUID = _getInitialAttestationUID(projectId);
        
//         // Initialize voting first with thresholds
//         vm.prank(ADMIN);
//         poc.initializeVoting(attestationUID, 1, 1); // Requires 1 DAO vote and 1 SubDAO vote
        
//         // DAO member votes
//         vm.prank(ADMIN);
//         poc.vote(attestationUID, uint256(IProofOfChange.MemberType.DAOMember), true);
        
//         // SubDAO member votes
//         vm.prank(SUBDAO_MEMBER);
//         poc.vote(attestationUID, 1, true); // Vote as SubDAO member for region 1
        
//         // Warp time to after voting period (7 days + 1 second)
//         vm.warp(block.timestamp + 7 days + 1);
        
//         // Finalize the vote
//         poc.finalizeVote(attestationUID);
        
//         // Verify vote status
//         assertTrue(poc.getAttestationApprovalStatus(attestationUID));
//     }

//     function testCannotVoteTwice() public {
//         // Create project as USER
//         vm.startPrank(USER);
//         bytes32 logbookUID = _createLogbookAttestation();
        
//         IProofOfChange.ProjectCreationData memory data = IProofOfChange.ProjectCreationData({
//             duration: 30 days,
//             requestedFunds: 1 ether,
//             regionId: 1,
//             logbookAttestationUID: logbookUID
//         });
        
//         bytes32 projectId = poc.createProject{value: 1 ether}(data);
        
//         // Create phase attestation
//         bytes32 phaseUID = poc.createPhaseAttestation(projectId, IProofOfChange.VoteType.Initial);
//         vm.stopPrank();

//         // First vote should succeed
//         vm.prank(ADMIN);
//         poc.vote(phaseUID, uint256(IProofOfChange.MemberType.DAOMember), true);

//         // Second vote should fail
//         vm.prank(ADMIN);
//         vm.expectRevert(abi.encodeWithSignature("AlreadyVoted()"));
//         poc.vote(phaseUID, uint256(IProofOfChange.MemberType.DAOMember), true);
//     }

//     /*//////////////////////////////////////////////////////////////
//                         PHASE PROGRESSION TESTS
//     //////////////////////////////////////////////////////////////*/

//     function testAdvancePhase() public {
//         // Create test project with region ID 1
//         bytes32 projectId = _createTestProject();
        
//         // Get initial attestation UID
//         (,,,,bytes32[] memory attestationUIDs) = poc.getProjectDetails(projectId);
//         bytes32 initialAttestationUID = attestationUIDs[uint256(IProofOfChange.VoteType.Initial)];
        
//         // Initialize voting for initial phase
//         vm.prank(ADMIN);
//         poc.initializeVoting(initialAttestationUID, 2, 3);
        
//         // DAO members vote
//         vm.prank(ADMIN);
//         poc.vote(initialAttestationUID, 2, true);
        
//         vm.prank(ADMIN);
//         poc.addDAOMember(address(4));
//         vm.prank(address(4));
//         poc.vote(initialAttestationUID, 2, true);
        
//         // SubDAO members vote
//         vm.prank(SUBDAO_MEMBER);
//         poc.vote(initialAttestationUID, 1, true);
        
//         vm.prank(ADMIN);
//         poc.addSubDAOMember(address(5), 1);
//         vm.prank(address(5));
//         poc.vote(initialAttestationUID, 1, true);
        
//         vm.prank(ADMIN);
//         poc.addSubDAOMember(address(6), 1);
//         vm.prank(address(6));
//         poc.vote(initialAttestationUID, 1, true);
        
//         // Warp time to after voting period (7 days + 1 second)
//         vm.warp(block.timestamp + 7 days + 1);
        
//         // Finalize vote
//         poc.finalizeVote(initialAttestationUID);
        
//         // Verify attestation is approved
//         assertTrue(poc.getAttestationApprovalStatus(initialAttestationUID), "Attestation not approved");
        
//         // Advance to progress phase using the project proposer
//         vm.prank(USER);
//         poc.advanceToNextPhase(projectId);
        
//         // Verify phase advanced
//         (,,,IProofOfChange.VoteType currentPhase,) = poc.getProjectDetails(projectId);
//         assertEq(uint256(currentPhase), uint256(IProofOfChange.VoteType.Progress));
//     }

//     /*//////////////////////////////////////////////////////////////
//                             HELPER FUNCTIONS
//     //////////////////////////////////////////////////////////////*/

//     function _createMockAttestation() internal returns (bytes32) {
//         // Prepare the attestation data with fixed values
//         bytes memory attestationData = abi.encode(
//             uint256(1),  // Fixed value instead of block.timestamp
//             "test_event",
//             "test_location",
//             "test_memo"
//         );
        
//         AttestationRequest memory request = AttestationRequest({
//             schema: mockEAS.LOGBOOK_SCHEMA(),
//             data: AttestationRequestData({
//                 recipient: address(0),
//                 expirationTime: 0,
//                 revocable: true,
//                 refUID: bytes32(0),
//                 data: attestationData,
//                 value: 0
//             })
//         });
        
//         // Set msg.sender to USER before calling attest
//         vm.startPrank(USER);
//         bytes32 uid = mockEAS.attest(request);
        
//         // Verify the attestation was created correctly
//         Attestation memory att = mockEAS.getAttestation(uid);
//         require(att.attester == USER, "Wrong attester");
//         require(att.revocationTime == 0, "Attestation should not be revoked");
//         require(att.revocable == true, "Attestation should be revocable");
        
//         vm.stopPrank();
        
//         return uid;
//     }

//     function _createTestProject() internal returns (bytes32) {
//         bytes32 attestationUID = _createMockAttestation();
        
//         IProofOfChange.ProjectCreationData memory data = IProofOfChange.ProjectCreationData({
//             regionId: 1,
//             requestedFunds: INITIAL_FUNDS,
//             duration: 30 days,
//             logbookAttestationUID: attestationUID
//         });
        
//         vm.prank(USER);
//         return poc.createProject{value: INITIAL_FUNDS}(data);
//     }

//     function _getInitialAttestationUID(bytes32 projectId) internal view returns (bytes32) {
//         (,,,,bytes32[] memory attestationUIDs) = poc.getProjectDetails(projectId);
//         return attestationUIDs[0];
//     }

//     function _approvePhase(bytes32 projectId, IProofOfChange.VoteType phase) internal {
//         // Get project details to know the region
//         (,,,, bytes32[] memory attestationUIDs) = poc.getProjectDetails(projectId);
        
//         // Create phase attestation if it doesn't exist
//         bytes32 attestationUID;
//         if (phase == IProofOfChange.VoteType.Initial) {
//             attestationUID = attestationUIDs[uint256(phase)];
//         } else {
//             vm.prank(USER);
//             attestationUID = poc.createPhaseAttestation(projectId, phase);
//         }
        
//         // Initialize voting for both DAO and SubDAO members
//         vm.prank(ADMIN);
//         poc.initializeVoting(attestationUID, 2, 3); // 2 DAO votes, 3 SubDAO votes required
        
//         // First DAO member vote
//         vm.prank(ADMIN);
//         poc.vote(attestationUID, uint256(IProofOfChange.MemberType.DAOMember), true);
        
//         // Second DAO member vote
//         vm.prank(ADMIN);
//         poc.addDAOMember(address(4));
//         vm.prank(address(4));
//         poc.vote(attestationUID, uint256(IProofOfChange.MemberType.DAOMember), true);
        
//         // SubDAO members vote
//         vm.prank(SUBDAO_MEMBER);
//         poc.vote(attestationUID, 1, true);
        
//         vm.prank(ADMIN);
//         poc.addSubDAOMember(address(5), 1);
//         vm.prank(address(5));
//         poc.vote(attestationUID, 1, true);
        
//         vm.prank(ADMIN);
//         poc.addSubDAOMember(address(6), 1);
//         vm.prank(address(6));
//         poc.vote(attestationUID, 1, true);
        
//         // Warp time to after voting period
//         vm.warp(block.timestamp + 7 days + 1);
        
//         // Finalize the vote
//         poc.finalizeVote(attestationUID);
        
//         // Verify state change
//         vm.prank(ADMIN);
//         poc.verifyStateChange(projectId, phase, true);
        
//         // Advance to next phase if needed
//         if (phase != IProofOfChange.VoteType.Completion) {
//             vm.prank(USER);
//             poc.advanceToNextPhase(projectId);
//         }
//     }

//     /*//////////////////////////////////////////////////////////////
//                             FUND RELEASE TESTS
//     //////////////////////////////////////////////////////////////*/

//     function testReleasePhaseFunds() public {
//         bytes32 projectId = _createTestProject();
        
//         // Complete all phases
//         _approvePhase(projectId, IProofOfChange.VoteType.Initial);
//         _approvePhase(projectId, IProofOfChange.VoteType.Progress);
//         _approvePhase(projectId, IProofOfChange.VoteType.Completion);
        
//         // Record initial balance
//         uint256 initialBalance = USER.balance;
        
//         // Mark project as completed (now should work since all phases are approved)
//         vm.prank(ADMIN);
//         poc.updateProjectStatus(projectId, IProofOfChange.ProjectStatus.Completed);
        
//         // Release funds for initial phase
//         poc.releasePhaseFunds(projectId, IProofOfChange.VoteType.Initial);
        
//         // Verify funds released
//         (uint256 initialWeight,,) = poc.getCurrentPhaseWeights(projectId);
//         uint256 expectedRelease = (INITIAL_FUNDS * initialWeight) / 100;
//         assertEq(USER.balance, initialBalance + expectedRelease);
//         assertTrue(poc.phaseFundsReleased(projectId, IProofOfChange.VoteType.Initial));
//     }

//     function testCannotReleaseFundsTwice() public {
//         // Add DAO members
//         vm.prank(ADMIN);
//         poc.addDAOMember(USER);
//         vm.prank(ADMIN);
//         poc.addDAOMember(ADMIN);

//         // Add subDAO members for region 1
//         address subDao1 = address(0x3333);
//         address subDao2 = address(0x4444);
//         vm.prank(ADMIN);
//         poc.addSubDAOMember(subDao1, 1);
//         vm.prank(ADMIN);
//         poc.addSubDAOMember(subDao2, 1);
        
//         // Create initial logbook attestation
//         vm.startPrank(USER);
//         bytes32 logbookUID = _createLogbookAttestation();
        
//         // Create project
//         IProofOfChange.ProjectCreationData memory data = IProofOfChange.ProjectCreationData({
//             duration: 30 days,
//             requestedFunds: 1 ether,
//             regionId: 1,
//             logbookAttestationUID: logbookUID
//         });
        
//         bytes32 projectId = poc.createProject{value: 1 ether}(data);
        
//         // Initial phase attestation
//         bytes32 initialPhaseUID = poc.createPhaseAttestation(projectId, IProofOfChange.VoteType.Initial);
//         vm.stopPrank();
        
//         // DAO votes
//         vm.prank(ADMIN);
//         poc.vote(initialPhaseUID, 2, true);
//         vm.prank(USER);
//         poc.vote(initialPhaseUID, 2, true);
//         vm.prank(subDao1);
//         poc.vote(initialPhaseUID, 1, true);
//         vm.prank(subDao2);
//         poc.vote(initialPhaseUID, 1, true);
        
//         vm.warp(block.timestamp + 7 days + 1);
//         poc.finalizeVote(initialPhaseUID);
        
//         // Verify state change
//         vm.prank(ADMIN);
//         poc.verifyStateChange(projectId, IProofOfChange.VoteType.Initial, true);
        
//         // Progress phase
//         vm.startPrank(USER);
//         poc.advanceToNextPhase(projectId);
//         bytes32 progressPhaseUID = poc.createPhaseAttestation(projectId, IProofOfChange.VoteType.Progress);
//         vm.stopPrank();
        
//         // Progress phase voting
//         vm.prank(ADMIN);
//         poc.vote(progressPhaseUID, 2, true);
//         vm.prank(USER);
//         poc.vote(progressPhaseUID, 2, true);
//         vm.prank(subDao1);
//         poc.vote(progressPhaseUID, 1, true);
//         vm.prank(subDao2);
//         poc.vote(progressPhaseUID, 1, true);
        
//         vm.warp(block.timestamp + 7 days + 1);
//         poc.finalizeVote(progressPhaseUID);
        
//         vm.prank(ADMIN);
//         poc.verifyStateChange(projectId, IProofOfChange.VoteType.Progress, true);
        
//         // Completion phase
//         vm.startPrank(USER);
//         poc.advanceToNextPhase(projectId);
//         bytes32 completionPhaseUID = poc.createPhaseAttestation(projectId, IProofOfChange.VoteType.Completion);
//         vm.stopPrank();
        
//         // Completion phase voting
//         vm.prank(ADMIN);
//         poc.vote(completionPhaseUID, 2, true);
//         vm.prank(USER);
//         poc.vote(completionPhaseUID, 2, true);
//         vm.prank(subDao1);
//         poc.vote(completionPhaseUID, 1, true);
//         vm.prank(subDao2);
//         poc.vote(completionPhaseUID, 1, true);
        
//         vm.warp(block.timestamp + 7 days + 1);
//         poc.finalizeVote(completionPhaseUID);
        
//         vm.prank(ADMIN);
//         poc.verifyStateChange(projectId, IProofOfChange.VoteType.Completion, true);
        
//         // Mark as completed
//         vm.prank(ADMIN);
//         poc.updateProjectStatus(projectId, IProofOfChange.ProjectStatus.Completed);
        
//         // Release funds for Initial phase
//         poc.releasePhaseFunds(projectId, IProofOfChange.VoteType.Initial);
        
//         // Try to release funds again (should fail)
//         vm.expectRevert(IProofOfChange.FundsAlreadyReleased.selector);
//         poc.releasePhaseFunds(projectId, IProofOfChange.VoteType.Initial);
//     }

//     function _createLogbookAttestation() internal returns (bytes32) {
//         bytes32 schema = mockEAS.LOGBOOK_SCHEMA();
//         bytes memory data = abi.encode(
//             1,                  // regionId
//             "test_event",      // event
//             "test_location",   // location
//             "test_memo"        // memo
//         );
        
//         AttestationRequest memory request = AttestationRequest({
//             schema: schema,
//             data: AttestationRequestData({
//                 recipient: address(0),
//                 expirationTime: 0,
//                 revocable: true,
//                 refUID: bytes32(0),
//                 data: data,
//                 value: 0
//             })
//         });
        
//         return mockEAS.attest(request);
//     }

//     /*//////////////////////////////////////////////////////////////
//                             EMERGENCY TESTS
//     //////////////////////////////////////////////////////////////*/

//     function testEmergencyProjectFreeze() public {
//         bytes32 projectId = _createTestProject();
        
//         // Complete initial phase approval first
//         (,,,,bytes32[] memory attestationUIDs) = poc.getProjectDetails(projectId);
//         bytes32 initialAttestationUID = attestationUIDs[uint256(IProofOfChange.VoteType.Initial)];
        
//         // Initialize and complete voting
//         vm.prank(ADMIN);
//         poc.initializeVoting(initialAttestationUID, 2, 2);
        
//         vm.prank(ADMIN);
//         poc.vote(initialAttestationUID, 2, true);
        
//         vm.prank(ADMIN);
//         poc.addDAOMember(address(4));
//         vm.prank(address(4));
//         poc.vote(initialAttestationUID, 2, true);
        
//         // Wait for voting period to end
//         vm.warp(block.timestamp + 7 days + 1);
//         poc.finalizeVote(initialAttestationUID);
        
//         // Emergency freeze
//         vm.prank(ADMIN);
//         poc.emergencyProjectAction(projectId, 7 days);
        
//         // Verify frozen status
//         assertTrue(poc.projectFrozenUntil(projectId) > block.timestamp);
        
//         // Get the freeze end time for the error check
//         uint256 freezeEndTime = poc.projectFrozenUntil(projectId);
        
//         // Use the exact error selector and encoding from the trace
//         bytes memory expectedError = abi.encodeWithSelector(
//             bytes4(0xc3fd1c80),  // ProjectIsFrozen selector
//             projectId,
//             freezeEndTime
//         );
//         vm.expectRevert(expectedError);
        
//         vm.prank(USER);
//         poc.advanceToNextPhase(projectId);
//     }

//     function testEmergencyPause() public {
//         // Emergency pause by admin
//         vm.prank(ADMIN);
//         poc.emergencyPause(IProofOfChange.FunctionGroup.ProjectCreation);
        
//         // Verify pause status
//         (bool isPaused, uint256 pauseEnds, bool isPermaPaused) = poc.pauseConfigs(IProofOfChange.FunctionGroup.ProjectCreation);
//         console.log("Pause Status:");
//         console.log("isPaused:", isPaused);
//         console.log("pauseEnds:", pauseEnds);
//         console.log("current timestamp:", block.timestamp);
//         console.log("isPermaPaused:", isPermaPaused);
        
//         assertTrue(isPaused);
//         assertEq(pauseEnds, block.timestamp + poc.EMERGENCY_PAUSE_DURATION());
        
//         // Create mock attestation
//         bytes32 attestationUID = _createMockAttestation();
        
//         // Attempt action while paused
//         IProofOfChange.ProjectCreationData memory data = IProofOfChange.ProjectCreationData({
//             regionId: 1,
//             requestedFunds: INITIAL_FUNDS,
//             duration: 30 days,
//             logbookAttestationUID: attestationUID
//         });
        
//         // Make sure we're still in the pause period
//         assertLt(block.timestamp, pauseEnds, "Should still be in pause period");
        
//         // Attempt to create project while paused (should fail)
//         vm.prank(USER);
        
//         // Update to match the actual error being thrown
//         vm.expectRevert(abi.encodeWithSelector(
//             IProofOfChange.FunctionCurrentlyPaused.selector,
//             IProofOfChange.FunctionGroup.ProjectCreation,
//             pauseEnds
//         ));
        
//         poc.createProject{value: INITIAL_FUNDS}(data);
//     }

//     /*//////////////////////////////////////////////////////////////
//                             ADMIN FUNCTION TESTS
//     //////////////////////////////////////////////////////////////*/

//     function testAddDAOMember() public {
//         address newMember = address(4);
        
//         vm.prank(ADMIN);
//         poc.addDAOMember(newMember);
        
//         assertEq(uint256(poc.members(newMember)), uint256(IProofOfChange.MemberType.DAOMember));
//     }

//     function testUpdateMember() public {
//         address member = address(4);
        
//         // Add as DAO member first
//         vm.prank(ADMIN);
//         poc.addDAOMember(member);
        
//         // Update to SubDAO member with regionId
//         vm.prank(ADMIN);
//         poc.updateMember(member, IProofOfChange.MemberType.SubDAOMember, 1);
        
//         assertEq(uint256(poc.members(member)), uint256(IProofOfChange.MemberType.SubDAOMember));
//         assertTrue(poc.regionSubDAOMembers(1, member));
//     }
}
