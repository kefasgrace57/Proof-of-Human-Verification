# 🔐 Proof-of-Human Verification Contract

A Sybil-resistant smart contract for human verification on the Stacks blockchain ⛓️

## 🎯 Overview

This contract implements a proof-of-human verification system designed to prevent Sybil attacks by requiring stake deposits, peer vouching, and challenge-response mechanisms. Users must stake STX tokens, receive vouches from verified humans, and respond to challenges to maintain their verified status.

## ✨ Features

- 🏦 **Stake-based Registration**: Users must stake STX tokens to register
- 🤝 **Peer Vouching System**: Verified humans can vouch for new registrants  
- ⚔️ **Challenge-Response**: Users can challenge suspicious accounts
- 🛡️ **Sybil Resistance**: Multiple mechanisms prevent fake account creation
- 📊 **Verification Tracking**: Monitor verification status and statistics
- ⏸️ **Emergency Controls**: Contract owner can pause/unpause operations

## 🚀 Quick Start

### Deploy Contract
```bash
clarinet deploy
```

### Register as Human
```bash
clarinet console
```

```clarity
(contract-call? .proof-of-human-verification register-human 0x1234567890abcdef)
```

### Vouch for Another User
```clarity
(contract-call? .proof-of-human-verification vouch-for-human 'SP1234567890ABCDEF)
```

### Check Verification Status
```clarity
(contract-call? .proof-of-human-verification is-verified 'SP1234567890ABCDEF)
```

## 📋 Usage Guide

### 1. Bootstrap Initial Verification 👑
Only the contract owner can bootstrap the first verified human:

```clarity
(contract-call? .proof-of-human-verification bootstrap-verification)
```

### 2. Register as Human 📝
Users must stake minimum STX tokens and provide proof hash:

```clarity
(contract-call? .proof-of-human-verification register-human 0xproof-hash)
```

**Requirements:**
- Minimum 1,000,000 micro-STX stake
- Unique proof hash
- No existing registration

### 3. Vouch for Others 🤝
Verified humans can vouch for pending registrations:

```clarity
(contract-call? .proof-of-human-verification vouch-for-human 'SP-target-address)
```

**Requirements:**
- Voucher must be verified
- Cannot self-vouch
- Each voucher can only vouch once per target
- Target needs 3 vouches to become verified

### 4. Challenge Verification ⚔️
Verified users can challenge suspicious accounts:

```clarity
(contract-call? .proof-of-human-verification create-challenge 'SP-target 0xchallenge-data)
```

### 5. Respond to Challenges 💬
Challenged users must respond within 144 blocks:

```clarity
(contract-call? .proof-of-human-verification respond-to-challenge u1 0xresponse-data)
```

### 6. Withdraw Stake 💰
Non-verified users can withdraw their stake:

```clarity
(contract-call? .proof-of-human-verification withdraw-stake)
```

## 🔍 Read-Only Functions

### Check User Information
```clarity
(contract-call? .proof-of-human-verification get-user-info 'SP-address)
```

### Verify Human Status
```clarity
(contract-call? .proof-of-human-verification is-verified 'SP-address)
```

### Get Total Verified Count
```clarity
(contract-call? .proof-of-human-verification get-verification-count)
```

### Check Vouch Status
```clarity
(contract-call? .proof-of-human-verification has-vouched 'SP-voucher 'SP-vouchee)
```

## 📊 Contract Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `min-stake` | 1,000,000 | Minimum STX stake required |
| `required-vouches` | 3 | Vouches needed for verification |
| `challenge-duration` | 144 | Blocks to respond to challenges |

## 🛠️ Error Codes

| Code | Description |
|------|-------------|
| u100 | Owner only operation |
| u101 | User not found |
| u102 | User already exists |
| u103 | Insufficient stake |
| u104 | Not verified |
| u105 | Cannot self-vouch |
| u106 | Already vouched |
| u107 | Insufficient vouches |
| u108 | Invalid challenge |
| u109 | Challenge expired |
| u110 | Contract paused |
| u111 | Contract not paused |

## 🔒 Security Features

- **Stake Requirements**: Economic barrier to entry
- **Vouching System**: Social proof mechanism  
- **Challenge System**: Ongoing verification checks
- **Emergency Controls**: Owner can pause for security
- **Unique Registrations**: One account per principal

## 🧪 Testing

Run tests with:
```bash
clarinet test
```

## 📈 Monitoring

Track verification statistics:
- Total verified humans
- Registration patterns
- Challenge success rates
- Stake distribution

## 🚨 Emergency Procedures

Contract owner can:
- Pause/unpause contract
- Emergency withdraw stakes
- Bootstrap initial verification

---

**⚠️ Important**: This is an MVP implementation. Production use requires thorough security auditing and additional features like appeal processes and governance mechanisms.

Made with ❤️ for Sybil-resistant verification on Stacks
