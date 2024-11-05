# ProofOfChange Protocol

ProofOfChange is a protocol that enables on-chain verification of environmental state changes through satellite imagery and location proofs. It integrates with Astral Protocol's Logbook for geotagged log entries and location proof generation.

## Overview

The protocol allows users to:
- Register environmental projects with satellite imagery proof
- Track progress through verifiable state changes
- Validate completed projects through DAO governance
- Release funds upon successful verification

## Architecture

### Core Components:
- **Smart Contracts**: Handles verification logic and fund management
- **Logbook Integration**: UI for registering and tracking state changes
- **EAS**: Provides on-chain attestations for location proofs

### Dependencies:
- [Astral Protocol Logbook](https://github.com/AstralProtocol/logbook/)
- [Ethereum Attestation Service (EAS)](https://github.com/ethereum-attestation-service/eas-contracts)

## Project Workflow

### 1. Project Registration

#### Steps:
1. Access Logbook UI
2. Upload satellite images of project area
3. Add project metadata (name, description, location)
4. Generate location proof via Astral Protocol
5. Initial funds locked in escrow

### 2. Initial Verification
- Governance review:
  - DAOs:
    - Project eligibility through Logbook data
    - Location proof validity
    - Project scope and requirements
  - SubDAOs:
    - Confirms physical location
    - Verifies initial state on ground
    - Evaluates local feasibility
    - Assesses community impact
- Upon approval:
  - Project marked as active
  - Advances to monitoring phase

### 3. Progress Monitoring
- Project proposer submits updates via Logbook:
  - New satellite images showing changes
  - Progress metadata
  - Updated location proofs
- Governance review:
  - DAOs:
    - Compare before/after satellite images
    - Validate location proofs
    - Confirm milestone completion  
  - SubDAOs:
    - Confirm physical changes
    - Verify progress against milestones
    - Documents physical progress

### 4. Project Completion
- Final submission includes:
  - Final satellite images
  - Completion metadata
  - Final location proof
- Governance review:
  - DAOs:
    - Review data consistency across milestones
    - Review final state changes
    - Confirm project goals met
  - SubDAOs:
    - Performs final site inspection
Confirms physical completion
    - Documents final state
    - Provides completion report
- Fund distribution upon approval


## Future Enhancements (Phase 2)

1. Automated Verification
   - zkTLS for cryptographic image verification
   - zkML for automated state change analysis
   - Enhanced risk assessment

2. Treasury Optimization with Yield-Bearing Stablecoins
   - Smart Treasury Management:
     - Conversion of project funds to yield-bearing stablecoins
     - Automated yield strategy selection
     - Continuous yield optimization
     - Risk-adjusted position management    
   - Yield Distribution:
     - Validator incentives from generated yield
     - Protocol treasury growth
     - Additional stakeholder rewards
     - Performance-based distribution
   - Treasury Features:
     - Multi-strategy yield farming
     - Automated rebalancing
     - Risk assessment integration
     - Market condition adaptability
  
3. Enhanced Governance Features
   - Reputation system for DAO/SubDAO members
   - Automated coordination between remote and on-ground verification
   - Dispute resolution mechanism
   - Advanced analytics for verification patterns

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details
