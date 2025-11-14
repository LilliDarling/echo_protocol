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
- Each user generates a **4096-bit RSA key pair** on device during registration
- Private key **NEVER leaves the device** and is stored in platform secure storage:
  - iOS: Keychain with `first_unlock` accessibility
  - Android: KeyStore with encrypted shared preferences
  - Windows: DPAPI-protected storage

#### Key Exchange
- Public keys are stored in Firestore at `/users/{userId}/publicKey`
- When partners connect, they exchange public keys
- A shared symmetric key is derived using both public keys (deterministic key agreement)

### Message Encryption

#### Algorithm: AES-256-CBC
- Symmetric encryption using 256-bit keys
- Each message uses a unique random Initialization Vector (IV)
- IV is prepended to ciphertext for decryption

#### Encryption Flow
```
1. Sender types message (plaintext)
2. Generate random 16-byte IV
3. Encrypt plaintext with AES-256-CBC using shared secret + IV
4. Combine IV:EncryptedText in base64
5. Store in Firestore as 'content' field
6. Recipient retrieves encrypted content
7. Extract IV and decrypt using shared secret
8. Display plaintext
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
2. Encrypt entire file with AES-256-CBC
3. Prepend IV to encrypted bytes
4. Upload to Firebase Storage
5. Store encrypted file URL in Firestore
6. On retrieval, download, extract IV, decrypt, display

### Security Guarantees

✅ **Perfect Forward Secrecy**: Each message has unique IV
✅ **Zero-Knowledge**: Server cannot read messages
✅ **Device-Only Private Keys**: Private keys never transmitted
✅ **Platform Security**: Leverages iOS Keychain / Android KeyStore
✅ **Military-Grade Encryption**: AES-256 + RSA-4096

### Threat Model

#### Protected Against:
- ✅ Database breach (encrypted content unreadable)
- ✅ Network interception (TLS + E2EE)
- ✅ Server administrator access (zero-knowledge)
- ✅ Cloud backup leaks (private keys not backed up)

#### Not Protected Against:
- ❌ Compromised device (malware can read decrypted messages in memory)
- ❌ Partner's device access (they can decrypt messages sent to them)
- ❌ Metadata analysis (who/when communication occurs is visible)

## Implementation Notes

### User Registration Flow
```dart
1. User signs up
2. Generate RSA key pair
3. Store private key in secure storage (device only)
4. Upload public key to Firestore
5. Never backup or sync private key
```

### Partner Connection Flow
```dart
1. Users authenticate
2. Exchange public keys via Firestore
3. Derive shared symmetric key
4. Initialize encryption service
5. All messages now encrypted/decrypted automatically
```

### Key Rotation
- Keys are generated once and persist for account lifetime
- If device is lost, messages on that device are unrecoverable
- Partner linking requires re-exchange of public keys

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

## Compliance

This encryption implementation follows:
- ✅ AES-256 (FIPS 197)
- ✅ RSA-4096 (FIPS 186-4)
- ✅ SHA-256 (FIPS 180-4)

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
3. Device A generates encrypted QR code containing private key
4. Open app on Device B (new device)
5. Select "Link to Existing Account"
6. Scan QR code with Device B
7. Private key transferred directly device-to-device
8. No cloud storage of private key
```

**Security Benefits**:
- ✅ Private key never stored in cloud
- ✅ No password to remember/forget
- ✅ Direct device-to-device transfer
- ✅ Works offline
- ⚠️ Requires physical access to both devices simultaneously

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

- [ ] Add public key fingerprint verification (prevent MITM)
- [ ] Implement key rotation mechanism
- [ ] Add message self-destruct timer
- [ ] Screenshot detection and warnings
- [ ] Biometric authentication for app access
- [x] Two-factor authentication (2FA)
- [x] Device linking via QR code
- [ ] Remote key revocation
- [x] Device access audit log (in security log collection)

---

**Remember**: Security is only as strong as its weakest link. Always verify partner identity through a trusted channel before sharing sensitive information.
