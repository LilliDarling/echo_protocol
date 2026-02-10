# Echo Protocol - Security Architecture

## Overview

Echo Protocol implements **end-to-end encryption (E2EE)** to ensure that all message content is completely private between the two partners. Even if the database is compromised, message content remains unreadable.

## Encryption Architecture

### Multi-Layer Security

1. **Transport Layer**: HTTPS/TLS encryption for all data in transit
2. **Sealed Sender Layer**: Ephemeral X25519 ECDH + AES-256-GCM envelope hides sender identity from server
3. **Application Layer**: X3DH + Double Ratchet for message content
4. **Storage Layer**: SQLCipher-encrypted local database + platform-specific secure storage for private keys
5. **Media Layer**: Per-file encryption with unique keys

### Key Management

#### Key Generation
- Each user generates an **X25519 identity key pair** on device during registration
- **Security level**: 256-bit (Curve25519)
- Private key **NEVER leaves the device** and is stored in platform secure storage:
  - iOS: Keychain with `first_unlock` accessibility
  - Android: KeyStore with encrypted shared preferences
  - Windows: DPAPI-protected storage

#### X3DH Key Exchange (Extended Triple Diffie-Hellman)

The X3DH protocol establishes the initial shared secret between partners:

```
Identity Keys:     Long-term keys for user identity
Signed Prekeys:    Medium-term keys (rotated every 30 days)
One-Time Prekeys:  Single-use keys for forward secrecy
Ephemeral Keys:    Generated fresh for each session
```

**X3DH Process:**
1. Alice fetches Bob's **prekey bundle** (identity key + signed prekey + one-time prekey)
2. Alice verifies Bob's signed prekey signature
3. Alice generates an ephemeral key pair
4. Four DH operations compute the shared secret:
   - DH1: Alice's identity key ↔ Bob's signed prekey
   - DH2: Alice's ephemeral key ↔ Bob's identity key
   - DH3: Alice's ephemeral key ↔ Bob's signed prekey
   - DH4: Alice's ephemeral key ↔ Bob's one-time prekey (if available)
5. HKDF-SHA256 derives root key and initial chain key
6. One-time prekey is consumed and deleted (cannot be reused)

**Security Properties:**
- **Forward Secrecy**: Compromised identity key cannot decrypt past sessions
- **Deniability**: No cryptographic proof of who sent messages
- **Replay Protection**: One-time prekeys prevent session replay

#### Double Ratchet Protocol

After X3DH establishes the initial session, the Double Ratchet provides ongoing encryption:

```
Root Key ────► DH Ratchet ────► New Root Key
    │                              │
    └─► Chain Key ───► Message Keys (one per message)
```

**How It Works:**

1. **DH Ratchet (Asymmetric)**: Each party generates new X25519 key pairs
   - When receiving a message with new ratchet key, perform DH ratchet step
   - Computes new shared secret and derives new root/chain keys
   - Old private keys are securely deleted

2. **Chain Ratchet (Symmetric)**: Each chain key derives the next
   - Each message consumes the chain key and produces a new one
   - Message keys are derived from chain keys via HKDF
   - Old chain keys are deleted after use

3. **Message Keys**: Unique key per message
   - Derived from chain key using HKDF-SHA256
   - Used once for AES-256-GCM encryption
   - Immediately deleted after encryption/decryption

**Out-of-Order Message Handling:**
- Skipped message keys are stored temporarily (max 1000 per chain)
- Keys expire after 24 hours
- Allows decryption of delayed messages

**Security Guarantees:**
- **Forward Secrecy**: Compromise of current keys cannot decrypt past messages
- **Future Secrecy**: Compromise of current keys is healed by next ratchet step
- **Per-Message Keys**: Each message uses a unique encryption key
- **Key Deletion**: Used keys are securely cleared from memory

#### Public Key Fingerprint Verification
- Each public key has a unique **fingerprint** (SHA-256 hash displayed as 32 hex characters)
- Format: `1A2B 3C4D 5E6F 7A8B 9C0D 1E2F 3A4B 5C6D` (8 groups of 4)
- Users can verify fingerprints **out-of-band** (in-person, video call, voice call) to confirm identity
- Prevents man-in-the-middle attacks during key exchange
- Accessible via: Profile → Security Code

### Message Encryption

#### Algorithm: AES-256-GCM (Galois/Counter Mode)
- **Authenticated encryption** using 256-bit message keys
- Provides both **confidentiality** (encryption) and **authenticity** (tamper detection)
- Each message uses a unique key derived from the Double Ratchet chain
- **12-byte nonce** derived deterministically from message key via HKDF
- **Authentication tag** automatically generated and verified (prevents tampering)
- **Associated data** binds message to sender, recipient, and session context

#### Encryption Flow
```
1. Sender types message (plaintext)
2. Double Ratchet advances chain and derives unique message key
3. Encrypt plaintext with AES-256-GCM using message key
4. Build sender certificate (sender ID + Ed25519 public key + signature)
5. Assemble inner payload: [certificate length | certificate | encrypted message]
6. Pad inner payload to power-of-2 bucket (128B–64KB) with random fill
7. Generate ephemeral X25519 key pair
8. ECDH with recipient's X25519 public key → shared secret
9. HKDF-SHA256 derives sealed sender encryption key
10. Encrypt padded payload with AES-256-GCM → sealed envelope
11. Clear all intermediate key material from memory
12. Deliver sealed envelope to recipient's inbox via cloud function
13. Recipient performs ECDH with ephemeral public key → shared secret
14. Decrypt sealed envelope → recover padded inner payload
15. Unpad and extract sender certificate + encrypted message
16. Verify sender certificate signature (Ed25519)
17. Double Ratchet decrypts the inner message
18. Securely clear all intermediate buffers
19. Display plaintext
```

### What's Encrypted vs. Unencrypted

#### Encrypted (Unreadable in Database)
- ✅ Message content (text)
- ✅ Sender identity (inside sealed envelope, extracted only by recipient)
- ✅ Message type (inside sealed envelope)
- ✅ Sender certificate and signature (inside sealed envelope)
- ✅ File data (images, videos, voice messages)
- ✅ Link URLs in messages

#### Unencrypted (Metadata visible to server)
- ❌ Recipient ID (inbox routing requires knowing the recipient)
- ❌ Delivery timestamp (server-generated)
- ❌ Envelope expiry time
- ❌ Ciphertext size (mitigated by power-of-2 padding buckets)
- ❌ User names and avatars
- ❌ Partnership relationship (`users.partnerId` in Firestore)

### Media Encryption

Images, videos, and GIFs are encrypted independently with unique per-file keys:

#### Media Key Management
- Each media file gets a **unique 256-bit key** (not derived from message ratchet)
- Media key is generated using secure random
- Media key is encrypted within the message and sent to recipient
- Allows media to be decrypted independently of message order

#### Encryption Process
```
1. Read media file as bytes
2. Generate unique 32-byte media key (secure random)
3. Generate unique media ID (SHA-256 based)
4. Construct AAD: "EchoMedia:{mediaId}"
5. Generate 12-byte random nonce
6. Encrypt with AES-256-GCM using media key + nonce + AAD
7. Package: [nonce | ciphertext | auth tag]
8. Upload encrypted bytes to Firebase Storage
9. Include media key in encrypted message (protected by Double Ratchet)
10. On retrieval: download, decrypt with media key, cache locally
```

#### Security Properties
- **Independent Keys**: Media compromise doesn't affect message encryption
- **Per-File Isolation**: Each file has unique key and ID
- **Authenticated Encryption**: Tampering detection via GCM
- **Secure Caching**: Decrypted media cached in app-private storage

### Sealed Sender

Sealed sender prevents the server from learning who sent a message to whom on a per-message basis. The sender's identity is hidden inside the encrypted envelope and only revealed to the recipient after decryption.

#### How It Works
```
1. Sender creates a SenderCertificate:
   - Contains: sender ID + Ed25519 public key + timestamp
   - Signed with sender's Ed25519 private key
2. Build inner payload: [certificate length (2 bytes) | certificate | Double Ratchet ciphertext]
3. Pad to power-of-2 bucket (128, 256, 512, ... 65536 bytes):
   - Format: [4-byte big-endian length | payload | random fill]
   - Random fill prevents pattern analysis
4. Generate ephemeral X25519 key pair (single use)
5. ECDH: ephemeral private key × recipient's X25519 public key → shared secret
6. HKDF-SHA256 derives encryption key:
   - IKM: shared secret
   - Salt: "SealedSender-v1"
   - Info: ephemeral public key || recipient public key
7. Encrypt padded payload with AES-256-GCM
8. Package: [12-byte nonce | ciphertext | 16-byte GCM tag]
9. Securely clear: shared secret, encryption key, padded payload, inner payload
```

#### Security Properties
- **Sender Anonymity**: Server sees only the recipient ID and encrypted blob
- **Forward Secrecy**: Ephemeral key pair generated per message, never reused
- **Authenticated Sender**: Recipient verifies Ed25519 signature on sender certificate
- **Size Obfuscation**: Power-of-2 padding hides exact message length
- **Key Material Hygiene**: All intermediate secrets cleared from memory after use

#### What the Server Sees
```
Inbox document:
  sealedEnvelope:
    payload: <base64 encrypted blob>     # opaque
    ephemeralKey: <base64 32-byte key>    # single-use, not linkable
    timestamp: <creation time>
    expireAt: <24-hour TTL>
  deliveredAt: <server timestamp>
  expireAt: <7-day retention TTL>
```

The server cannot determine sender ID, message content, or message type from the inbox document.

### Local Database Encryption

All local data is stored in a SQLCipher-encrypted database.

#### Configuration
- **Encryption**: AES-256 via SQLCipher
- **Key**: 32-byte random key stored in platform secure storage
- **PRAGMAs**:
  - `cipher_memory_security = ON`: Wipe SQLCipher internal memory on free
  - `cipher_page_size = 4096`: Explicit page size for version consistency
  - `secure_delete = ON`: Overwrite deleted data with zeros
  - `temp_store = MEMORY`: Temp tables in memory, not on disk
  - `foreign_keys = ON`: Referential integrity

#### What's Stored Locally
- Decrypted message content (for display without re-decrypting)
- Conversation metadata (last message preview, unread count)
- Blocked user list
- Message status (pending/sent/delivered/failed)

### Security Guarantees

✅ **Forward Secrecy**: Compromise of current keys cannot decrypt past messages
✅ **Future Secrecy**: Key compromise is healed by next DH ratchet step
✅ **Per-Message Keys**: Each message uses a unique encryption key
✅ **Authenticated Encryption**: GCM mode prevents tampering and forgery
✅ **Replay Attack Protection**: Per-conversation sequence numbers and nonce tracking
✅ **Rate Limiting**: Soft blocking with exponential backoff prevents spam and abuse
✅ **Sealed Sender**: Server cannot see who sent a message
✅ **Message Padding**: Power-of-2 buckets prevent ciphertext length analysis
✅ **Blocked User Enforcement**: Messages from blocked users dropped after decryption
✅ **Zero-Knowledge**: Server cannot read messages
✅ **Local DB Encryption**: SQLCipher with secure memory wiping and secure delete
✅ **Device-Only Private Keys**: Private keys never transmitted
✅ **Platform Security**: Leverages iOS Keychain / Android KeyStore
✅ **Industry-Standard Encryption**: X25519 + AES-256-GCM + HKDF-SHA256
✅ **X3DH Key Agreement**: Secure initial key exchange with one-time prekeys
✅ **Double Ratchet**: Continuous key rotation for ongoing conversations
✅ **Fingerprint Verification**: Out-of-band verification prevents MITM attacks
✅ **Key Rotation**: Users can generate new identity keys when needed
✅ **Secure Key Deletion**: Used keys are cleared from memory immediately

### Threat Model

#### Protected Against:
- ✅ Database breach (encrypted content unreadable)
- ✅ Network interception (TLS + E2EE)
- ✅ Server administrator access (zero-knowledge)
- ✅ Cloud backup leaks (private keys not backed up)
- ✅ Message tampering (GCM authentication tags detect modifications)
- ✅ Replay attacks (sequence numbers + nonce tracking with 1-hour window)
- ✅ Message flooding/spam (rate limiting: 30 msg/min, 500/hour with soft blocking)
- ✅ Man-in-the-middle during key exchange

#### Not Protected Against:
- ❌ Compromised device (malware can read decrypted messages in memory)
- ❌ Partner's device access (they can decrypt messages sent to them)
- ❌ Server-side relationship metadata (`users.partnerId` reveals partnership; sealed sender hides per-message sender but server knows the relationship exists)
- ❌ Timing analysis (delivery timestamps visible to server)

## Implementation Notes

### User Registration Flow
```
1. User signs up
2. Generate X25519 identity key pair using secure random
3. Generate initial signed prekey (30-day validity)
4. Generate batch of one-time prekeys (100 keys)
5. Store private keys in secure storage (device only)
6. Upload public identity key and prekey bundle to Firestore
7. Never backup or sync private keys
```

### Partner Connection Flow
```
1. Users authenticate and link via invite code
2. Initiator fetches responder's prekey bundle
3. Verify signed prekey signature
4. Perform X3DH key agreement (4 DH operations)
5. Consume and delete one-time prekey
6. Initialize Double Ratchet session with derived keys
7. Generate initial ratchet key pair
8. All messages now use Double Ratchet encryption
```

### Message Send/Receive Flow
```
Sending:
1. Advance sending chain ratchet → derive unique message key
2. Encrypt plaintext with AES-256-GCM (Double Ratchet inner layer)
3. Build sender certificate with Ed25519 signature
4. Assemble inner payload → pad to power-of-2 bucket with random fill
5. Generate ephemeral X25519 key pair
6. ECDH with recipient's X25519 public key → derive sealed sender key via HKDF
7. Encrypt padded payload with AES-256-GCM (sealed sender outer layer)
8. Clear all intermediate key material from memory
9. Deliver sealed envelope to recipient's inbox via cloud function
10. Store local copy in SQLCipher-encrypted database

Receiving:
1. Firestore snapshot listener delivers sealed envelope from inbox
2. Check message ID for duplicate (idempotent reprocessing)
3. ECDH with ephemeral public key → derive decryption key via HKDF
4. Decrypt sealed envelope → unpad inner payload
5. Verify sender certificate (Ed25519 signature)
6. Extract sender ID from certificate (sealed sender reveal)
7. Check if sender is blocked → drop silently if yes
8. Double Ratchet decrypts inner message (DH ratchet step if needed)
9. Store decrypted message in SQLCipher-encrypted local database
10. Delete envelope from Firestore inbox
11. Clear all intermediate buffers from memory
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
- ✅ **X25519** (RFC 7748) - Elliptic curve Diffie-Hellman
- ✅ **Ed25519** (RFC 8032) - Digital signatures for prekey signing
- ✅ **HKDF-SHA256** (RFC 5869) - Key derivation function
- ✅ **SHA-256** (FIPS 180-4) - Cryptographic hashing
- ✅ **X3DH** - Extended Triple Diffie-Hellman key agreement
- ✅ **Double Ratchet** - Continuous key rotation with forward/future secrecy

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
- [x] X3DH key exchange (Extended Triple Diffie-Hellman)
- [x] Double Ratchet protocol (forward and future secrecy)
- [x] Per-message key derivation
- [x] Media encryption with independent keys
- [x] Out-of-order message handling
- [x] Sealed sender (sender identity hidden in encrypted envelope)
- [x] Message padding (power-of-2 buckets to prevent length analysis)
- [x] SQLCipher local database encryption with hardened PRAGMAs
- [x] Blocked user enforcement (messages silently dropped)
- [ ] Cross-device message vault (encrypted sent-message sync)
- [ ] Server-side block enforcement
- [ ] PreKey depletion protection (rate limit bundle retrieval)
- [ ] Add message self-destruct timer
- [ ] Screenshot detection and warnings
- [ ] Biometric authentication for app access
- [ ] Remote key revocation

---

**Remember**: Security is only as strong as its weakest link. Always verify partner identity through a trusted channel before sharing sensitive information.
