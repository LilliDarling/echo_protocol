# Echo Protocol - Security Architecture

## Overview

Echo Protocol implements **end-to-end encryption (E2EE)** to ensure that all message content is completely private between the two partners. Even if the database is compromised, message content remains unreadable.

## Encryption Architecture

### Multi-Layer Security

1. **Transport Layer**: HTTPS/TLS encryption for all data in transit
2. **Application Layer**: End-to-end encryption for message content
3. **Storage Layer**: Platform-specific secure storage for private keys

### Key Management

#### Key Generation
- Each user generates an **Elliptic Curve (secp256k1) key pair** on device during registration
- **Security level**: 256-bit (equivalent to RSA-3072, same curve used by Bitcoin and Signal)
- Private key **NEVER leaves the device** and is stored in platform secure storage:
  - iOS: Keychain with `first_unlock` accessibility
  - Android: KeyStore with encrypted shared preferences
  - Windows: DPAPI-protected storage

#### Key Exchange (ECDH - Elliptic Curve Diffie-Hellman)
- Public keys are stored in Firestore at `/users/{userId}/publicKey`
- When partners connect, they exchange public keys
- A shared symmetric key is derived using ECDH key agreement
- **Key Derivation**: HKDF-SHA256 (Signal Protocol standard) transforms the ECDH shared secret into a 256-bit AES key
- **Per-Conversation Salt**: Unique salt derived from both public keys ensures each conversation has a different encryption key

#### Public Key Fingerprint Verification
- Each public key has a unique **fingerprint** (SHA-256 hash displayed as 32 hex characters)
- Format: `1A2B 3C4D 5E6F 7A8B 9C0D 1E2F 3A4B 5C6D` (8 groups of 4)
- Users can verify fingerprints **out-of-band** (in-person, video call, voice call) to confirm identity
- Prevents man-in-the-middle attacks during key exchange
- Accessible via: Profile → Security Code

### Message Encryption

#### Algorithm: AES-256-GCM (Galois/Counter Mode)
- **Authenticated encryption** using 256-bit keys
- Provides both **confidentiality** (encryption) and **authenticity** (tamper detection)
- Each message uses a unique random 16-byte Initialization Vector (IV)
- **Authentication tag** automatically generated and verified (prevents tampering)
- IV is prepended to ciphertext for decryption

#### Encryption Flow
```
1. Sender types message (plaintext)
2. Generate random 16-byte IV using secure random generator
3. Encrypt plaintext with AES-256-GCM using shared secret + IV
4. GCM automatically generates authentication tag (prevents tampering)
5. Combine IV:EncryptedText (with embedded auth tag) in base64
6. Store in Firestore as 'content' field
7. Recipient retrieves encrypted content
8. Extract IV and decrypt using shared secret
9. GCM automatically verifies authentication tag (rejects if tampered)
10. Display plaintext
```

### What's Encrypted vs. Unencrypted

#### Encrypted (Unreadable in Database)
- ✅ Message content (text)
- ✅ File data (images, videos, voice messages)
- ✅ Link URLs in messages
- ✅ Gift idea descriptions (optional)
- ✅ Date idea descriptions (optional)

#### Unencrypted (Metadata for functionality)
- ❌ Sender ID
- ❌ Recipient ID
- ❌ Timestamp
- ❌ Message type (text/image/video/voice/link)
- ❌ Status (sent/delivered/read)
- ❌ User names and avatars
- ❌ File names (but not content)

### File Encryption

Images, videos, and voice messages are encrypted before upload to Firebase Storage:
1. Read file as bytes
2. Encrypt entire file with AES-256-GCM (authenticated encryption)
3. Prepend IV to encrypted bytes (with embedded authentication tag)
4. Upload to Firebase Storage
5. Store encrypted file URL in Firestore
6. On retrieval, download, extract IV, verify authentication tag, decrypt, display

### Security Guarantees

✅ **Authenticated Encryption**: GCM mode prevents tampering and forgery
✅ **Perfect Forward Secrecy**: Each message has unique IV
✅ **Replay Attack Protection**: Per-conversation sequence numbers and nonce tracking prevent message replay
✅ **Rate Limiting**: Soft blocking with exponential backoff prevents spam and abuse
✅ **Zero-Knowledge**: Server cannot read messages
✅ **Device-Only Private Keys**: Private keys never transmitted
✅ **Platform Security**: Leverages iOS Keychain / Android KeyStore
✅ **Industry-Standard Encryption**: AES-256-GCM + ECDH (secp256k1) + HKDF-SHA256
✅ **Signal Protocol Inspired**: Uses same key derivation approach as Signal
✅ **Per-Conversation Isolation**: Unique salt per conversation prevents cross-conversation key reuse
✅ **Fingerprint Verification**: Out-of-band verification prevents MITM attacks
✅ **Key Rotation**: Users can generate new encryption keys when needed

### Threat Model

#### Protected Against:
- ✅ Database breach (encrypted content unreadable)
- ✅ Network interception (TLS + E2EE)
- ✅ Server administrator access (zero-knowledge)
- ✅ Cloud backup leaks (private keys not backed up)
- ✅ Message tampering (GCM authentication tags detect modifications)
- ✅ Replay attacks (sequence numbers + nonce tracking with 1-hour window)
- ✅ Message flooding/spam (rate limiting: 30 msg/min, 500/hour with soft blocking)

#### Not Protected Against:
- ❌ Compromised device (malware can read decrypted messages in memory)
- ❌ Partner's device access (they can decrypt messages sent to them)
- ❌ Metadata analysis (who/when communication occurs is visible)
- ✅ ~~Man-in-the-middle during key exchange~~ - **MITIGATED** by public key fingerprint verification (implemented)

## Implementation Notes

### User Registration Flow
```dart
1. User signs up
2. Generate EC (secp256k1) key pair using secure random
3. Store private key in secure storage (device only)
4. Upload public key to Firestore
5. Never backup or sync private key
```

### Partner Connection Flow
```dart
1. Users authenticate
2. Exchange public keys via Firestore
3. Perform ECDH key agreement to generate shared point
4. Derive symmetric AES-256 key using HKDF-SHA256
5. Initialize encryption service with derived key
6. All messages now encrypted/decrypted automatically
```

### Key Rotation

Users can rotate their encryption keys at any time for enhanced security:

#### How to Rotate Keys
1. Go to **Profile** → **Rotate Encryption Keys**
2. Confirm the action (warns about invalidating existing conversations)
3. System generates new EC key pair
4. New public key uploaded to Firestore with version tracking
5. Old keys are replaced (overwrites - no archival needed)

#### When to Rotate Keys
- Suspected device compromise
- Security policy compliance (e.g., annual rotation)
- After device loss/theft recovery
- Periodic security hygiene

#### Key Rotation Data
Firestore stores rotation metadata:
- `publicKey`: New public key
- `publicKeyVersion`: Unix timestamp version
- `publicKeyRotatedAt`: ISO 8601 timestamp
- `publicKeyFingerprint`: New fingerprint
- `keyHistory/{version}`: Archived public keys for decryption

#### Impact
✅ **Backward Compatible**: Message history remains accessible:
1. Old keys archived locally and in Firestore
2. Existing messages decrypt using archived keys
3. New messages use new keys
4. Device linking transfers all key versions

#### Security Benefits
- Limits exposure window if keys were compromised
- Fresh cryptographic material
- Audit trail via security logging

## Replay Attack Protection

### Overview

Replay attacks occur when an attacker intercepts and retransmits valid encrypted messages. Even though the attacker can't read the content, retransmitting old messages can cause confusion or manipulate conversation context.

### Protection Mechanisms

Echo Protocol implements **multi-layered replay protection**:

#### 1. Per-Conversation Sequence Numbers
- Each conversation maintains a strictly incrementing sequence counter
- Messages must arrive in order with no gaps or duplicates
- Bidirectional: Alice↔Bob share the same sequence space
- Stored locally on device (survives app restarts)

#### 2. Message Nonce Tracking
- Each message ID is tracked for 1-hour window
- Duplicate message IDs are rejected automatically
- Nonces expire after 1 hour to prevent unbounded storage

#### 3. Timestamp Validation
- Messages must be timestamped within 1-hour window
- 2-minute clock skew tolerance for time synchronization issues
- Rejects messages too old or too far in future

### How It Works

```
Sender Side:
1. Get next sequence number for conversation (e.g., seq=5)
2. Create message with unique ID and timestamp
3. Encrypt message content
4. Store message with sequenceNumber=5

Receiver Side:
1. Receive message (id="msg-123", seq=5, timestamp=now)
2. Check if nonce "msg-123" seen before → reject if yes
3. Check if seq=5 > lastSeenSeq → reject if not advancing
4. Check if timestamp within 1-hour window → reject if expired
5. Store nonce and update lastSeenSeq=5
6. Decrypt and display message
```

### Attack Scenarios Prevented

✅ **Exact Message Replay**: Same message ID detected and rejected
✅ **Out-of-Order Delivery**: Non-advancing sequence numbers rejected
✅ **Delayed Message Attack**: Old timestamps outside window rejected
✅ **Crafted Messages**: Must have valid, advancing sequence number

### Storage and Performance

- **Sequence Numbers**: ~8 bytes per conversation (permanent)
- **Nonces**: ~100 bytes per message ID (1-hour TTL)
- **Cleanup**: Automatic removal of expired nonces every 10 minutes
- **Lookup**: O(1) constant time validation

### Configuration

```dart
Time Window: 1 hour (configurable)
Clock Skew Tolerance: 2 minutes
Nonce Expiry: 1 hour
Storage: Local (SharedPreferences)
```

## Rate Limiting

### Overview

Rate limiting prevents message spam, flooding attacks, and abuse by enforcing send limits with soft blocking and progressive delays.

### Dual-Layer Protection

#### 1. Global User Limits
- **30 messages per minute** across all conversations
- **500 messages per hour** across all conversations
- Applies to single user's total sending capacity

#### 2. Per-Conversation Limits
- **20 messages per minute** to specific partner
- **300 messages per hour** to specific partner
- Prevents targeting/harassment of single contact

### Enforcement Strategy: Soft Blocking

Rather than hard rejections, rate limiting uses **progressive delays**:

```
Messages 1-20: No delay (instant send)
Message 21: 100ms delay
Message 22: 150ms delay
Message 23: 225ms delay
...
Message 30+: Up to 30 seconds delay (capped)
```

**Exponential Backoff**: Delay increases by 1.5x per excess message

### How It Works

```
1. User attempts to send message
2. Check global and per-conversation limits
3. Calculate required delay (if any)
4. Apply delay (blocks send temporarily)
5. Record message attempt
6. Allow send to proceed
```

### Rate Limit Stats

Users can query their current usage:

```dart
stats = {
  'global': {
    'lastMinute': 15,
    'lastHour': 120,
    'percentageMinute': 50,  // 50% of limit used
    'percentageHour': 24     // 24% of limit used
  },
  'conversation': {
    'lastMinute': 5,
    'lastHour': 45,
    'percentageMinute': 25,
    'percentageHour': 15
  }
}
```

### Benefits

✅ **Prevents Spam**: Automatic throttling of excessive sending
✅ **Abuse Mitigation**: Makes flooding attacks impractical
✅ **Soft UX**: No hard errors, just progressive delays
✅ **Fair Usage**: Legitimate users unaffected by normal usage
✅ **Resource Protection**: Reduces server and database load

### Attack Scenarios Prevented

✅ **Message Flooding**: Rate limits prevent rapid-fire spam
✅ **Harassment**: Per-conversation limits protect recipients
✅ **Resource Exhaustion**: Server load distributed over time
✅ **DoS Attempts**: Exponential backoff makes attacks costly

### Storage and Performance

- **Attempts Tracking**: In-memory with 1-hour window
- **Cleanup**: Automatic removal every 10 minutes
- **Lookup**: O(1) constant time
- **Memory**: ~50 bytes per tracked attempt

### Configuration

```dart
Global Limits:
  - 30 messages/minute
  - 500 messages/hour

Per-Conversation Limits:
  - 20 messages/minute
  - 300 messages/hour

Backoff:
  - Min delay: 100ms
  - Max delay: 30 seconds
  - Multiplier: 1.5x
```

## Two-Factor Authentication (2FA)

### Enhanced Account Security

2FA adds an extra layer of protection beyond just username/password:

#### How It Works
```
1. User enables 2FA in settings
2. Scan QR code with authenticator app (Google Authenticator, Authy, etc.)
3. Enter 6-digit code from app
4. Receive 10 backup codes (store safely!)
5. Every login now requires: password + 6-digit code
```

#### What 2FA Protects Against
- ✅ **Stolen Password**: Attacker can't login without your phone
- ✅ **Database Breach**: Password hash leak doesn't compromise account
- ✅ **Phishing**: Even if you enter password on fake site, they can't login
- ✅ **Remote Attacks**: Attacker needs physical access to your auth device

#### What 2FA Does NOT Protect Against
- ❌ **Compromised Device**: If your phone is hacked, attacker has both factors
- ❌ **Physical Device Theft**: If attacker has your unlocked phone + access
- ❌ **Malware on Device**: Keylogger could capture both password and 2FA code

### 2FA + E2EE = Maximum Security

Combined together:
```
Login Security (2FA):
- Password (something you know)
- TOTP code (something you have)

Message Security (E2EE):
- Private encryption key (stored on device)
- Partner's public key
```

**Result**: Even if someone gets your password, they can't:
1. Login to your account (needs 2FA code)
2. Read your messages (needs private encryption key)

### Backup Codes

When enabling 2FA, you receive 10 backup codes:
- Use if you lose access to authenticator app
- Each code works only once
- Store in password manager or safe place
- Can regenerate anytime (requires 2FA verification)

### Recovery Scenarios

**Lost Phone with Authenticator App**:
```
1. Use backup code to login
2. Disable 2FA temporarily
3. Set up 2FA on new device
4. Generate new backup codes
```

**Lost Backup Codes + Lost Phone**:
```
⚠️ Account recovery impossible without partner's help
Consider: Partner-assisted recovery (future feature)
```

## Privacy Features

### Auto-Delete
- Messages can auto-delete after N days (user preference)
- Deletion is permanent and unrecoverable

### Notifications
- Push notifications show "New message from [Partner]"
- Content is NOT included in notification
- User must open app to decrypt and read

## Compliance & Standards

This encryption implementation follows:
- ✅ **AES-256-GCM** (FIPS 197) - NIST approved authenticated encryption
- ✅ **ECDH with secp256k1** - Elliptic curve key agreement (same as Bitcoin, Signal)
- ✅ **HKDF-SHA256** (RFC 5869) - Key derivation function
- ✅ **SHA-256** (FIPS 180-4) - Cryptographic hashing
- ✅ **Signal Protocol Principles** - Industry-leading E2EE messaging standard

## Development Best Practices

1. **Never log decrypted content**
2. **Clear sensitive data from memory after use**
3. **Don't store plaintext in shared preferences**
4. **Test encryption/decryption in unit tests**
5. **Verify public key authenticity during partner connection**

## Multi-Device Access

### The Challenge
Private keys are stored only on the device that generated them. This creates a problem:
- Switch devices = lose access to old messages
- New device cannot decrypt messages encrypted with old key

### Solution: Device Linking via QR Code

For maximum security without cloud backup:
```
1. Open app on Device A (existing device with keys)
2. Go to Settings → Link New Device
3. Device A generates encrypted QR code containing private key + archived keys
4. Open app on Device B (new device)
5. Select "Link to Existing Account"
6. Scan QR code with Device B
7. All keys transferred directly device-to-device (encrypted with AES-256-GCM)
8. No cloud storage of private keys
```

**Security Features**:
- ✅ Private keys never stored in cloud
- ✅ All historical keys transferred (archived key pairs included)
- ✅ AES-256-GCM authenticated encryption for transfer
- ✅ 2-minute expiration window (configurable)
- ✅ One-time use tokens (automatically invalidated)
- ✅ Immediate Firestore cleanup after successful link
- ✅ Session keys with 256-bit entropy
- ✅ Strict Firestore security rules prevent unauthorized access
- ✅ Key version tracking for backward compatibility
- ⚠️ Requires physical access to both devices simultaneously

**Access Control**:
- Only authenticated users can read linking sessions
- Users can only read their own sessions OR valid unused sessions
- Self-linking is prevented (cannot link to your own session)
- Expired or used sessions are inaccessible
- Comprehensive field validation prevents malformed data

**Note**: If you lose all devices with your private key, messages become unrecoverable. This is the trade-off for maximum security.

## Device Compromise Scenarios

### What If Your Phone Is Hacked?

If your device is compromised (malware, physical access):

**Attacker CAN:**
- ❌ Read all messages you've already decrypted in the app
- ❌ Extract your private key from secure storage
- ❌ Decrypt future messages sent to you
- ❌ Impersonate you and send messages as you

**Attacker CANNOT:**
- ✅ Decrypt messages on other devices (each device has separate keys if no backup)
- ✅ Access messages that were auto-deleted
- ✅ Decrypt messages if you remotely revoke your keys (future feature)

### Mitigation Strategies

1. **Device Security**:
   - Enable device encryption
   - Use strong PIN/password/biometric
   - Keep OS and security patches updated
   - Install from trusted sources only

2. **App-Level Protection**:
   - Require biometric authentication to open app
   - Auto-lock after inactivity
   - Clear messages from memory after viewing
   - Screenshot detection and warnings

3. **Remote Protection** (Future):
   - Remote key revocation if device is lost/stolen
   - Force re-authentication on all devices
   - Audit log of device access

### Device Lost/Stolen Protocol

If your device is compromised:

```
1. Immediately change your account password
2. Revoke your encryption keys (forces new key generation)
3. Notify your partner
4. Old messages become unreadable (if auto-delete is enabled)
5. New messages use new keys
```

## Security Best Practices

### For Maximum Security:
1. **Single device only** (no key transfer)
2. Enable 2FA with authenticator app
3. Enable auto-delete for old messages (7-30 days)
4. Use biometric authentication
5. Enable screenshot detection
6. Regularly verify you're talking to your actual partner

### For Convenience with Good Security:
1. Enable 2FA with backup codes stored safely
2. Link devices via QR code when needed
3. Set reasonable auto-delete period (30 days)
4. Enable app-level authentication
5. Trust your device security

## Future Enhancements

- [x] Add public key fingerprint verification (prevent MITM)
- [x] Implement key rotation mechanism
- [x] Replay attack protection (sequence numbers + nonce tracking)
- [x] Rate limiting (dual-layer with soft blocking)
- [x] Two-factor authentication (2FA)
- [x] Device linking via QR code
- [x] Device access audit log (in security log collection)
- [ ] Add message self-destruct timer
- [ ] Screenshot detection and warnings
- [ ] Biometric authentication for app access
- [ ] Remote key revocation
- [ ] Cross-device sequence synchronization

---

**Remember**: Security is only as strong as its weakest link. Always verify partner identity through a trusted channel before sharing sensitive information.
