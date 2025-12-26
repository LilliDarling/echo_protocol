# Echo Protocol

A private, secure communication app designed for couples to stay connected, share moments, and cherish their relationship - no matter the distance.

## Overview

Echo Protocol is a Flutter-based mobile application that provides a dedicated, intimate space for partners to communicate and connect. More than just a messaging app, it's a relationship companion that helps couples share their thoughts, feelings, and memories in creative ways while keeping track of the experiences they want to share together.

## Features

### Communication
- **Private Messaging**: Send secure, encrypted messages exclusively between you and your partner
- **Media Sharing**: Share images and videos with automatic compression and encryption
- **GIF Sharing**: Express yourself with animated messages via Giphy integration
- **Link Previews**: Automatic rich previews for shared URLs
- **Typing Indicators**: See when your partner is typing in real-time
- **Read Receipts**: Know when your messages have been delivered and read
- **Message Status Tracking**: Visual indicators for pending, sent, delivered, and read states
- **Offline Support**: Queue messages while offline for automatic delivery when reconnected

### Shared Planning
- **Gift Ideas Tracker**: Keep track of gift ideas for your partner without them seeing *(planned)*
- **Date Ideas Collection**: Build a shared collection of date ideas to try together *(planned)*
- **Shared Experiences**: Track activities you've done together and things you want to do in the future *(planned)*

### Security & Privacy
- **End-to-End Encryption**: Military-grade AES-256-GCM encryption for all messages and files
- **Authentication Tag Verification**: Explicit validation of GCM authentication tags prevents tampering
- **Enhanced Key Encoding**: Binary key format with versioning and comprehensive validation
- **Public Key Fingerprint Verification**: Verify conversation partners via QR codes or security codes
- **Key Rotation with Backward Compatibility**: Rotate encryption keys without losing access to old messages
- **Replay Attack Protection**: Per-conversation sequence numbers and nonce tracking prevent message replay
- **Rate Limiting**: Soft blocking with exponential backoff prevents spam and abuse (30 msg/min, 500/hour)
- **Two-Factor Authentication**: TOTP-based 2FA with backup codes
- **Recovery Phrases**: BIP39 12-word mnemonic phrases for account recovery
- **Device Management**: Link multiple devices with encrypted private key transfer
- **Secure Storage**: Platform-specific secure storage (iOS Keychain, Android EncryptedSharedPreferences)
- **Zero-Knowledge Architecture**: Server cannot read your encrypted messages
- **Screenshot Protection**: Anti-screenshot mechanisms for sensitive screens

See [SECURITY.md](docs/SECURITY.md) for complete security architecture details.

## Technology Stack

### Frontend
- **Framework**: Flutter 3.9.2+
- **Language**: Dart
- **Platforms**: Android, iOS, Windows, Web
- **UI**: Material Design with light/dark theme support

### Backend
- **Cloud Infrastructure**: Firebase
  - Firebase Authentication (Email/Password, Google Sign-In)
  - Cloud Firestore (Database with TTL policies)
  - Firebase Storage (Media files)
  - Firebase Cloud Functions (Server-side validation)
  - Firebase Cloud Messaging (Push notifications)

### Cryptography
- **Encryption**: AES-256-GCM
- **Key Exchange**: ECDH with secp256k1 curve
- **Key Derivation**: HKDF-SHA256, PBKDF2
- **Recovery**: BIP39 mnemonic phrases

## Project Structure

```
echo_protocol/
├── lib/
│   ├── main.dart                 # Application entry point
│   ├── core/theme/               # Theme definitions
│   ├── features/                 # Feature modules
│   │   ├── auth/                 # Authentication screens
│   │   ├── home/                 # Home/Dashboard
│   │   ├── messages/             # Messaging UI
│   │   ├── profile/              # User profile
│   │   └── settings/             # Settings & security
│   ├── models/                   # Data models
│   ├── services/                 # Business logic (18 services)
│   ├── widgets/                  # Reusable UI components
│   └── utils/                    # Utility functions
├── functions/                    # Firebase Cloud Functions (TypeScript)
│   └── src/
│       ├── functions/            # Callable functions
│       ├── services/             # Rate limiting, anomaly detection
│       └── utils/                # Hashing, validation
├── firestore.rules               # Firestore security rules
├── storage.rules                 # Storage access rules
└── pubspec.yaml                  # Dart dependencies
```

## Getting Started

### Prerequisites
- Flutter SDK (^3.9.2)
- Dart SDK
- Firebase account
- iOS/Android development environment (Xcode/Android Studio)
- Node.js 22+ (for Cloud Functions)

### Installation

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd echo_protocol
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Configure Firebase:
   - Follow Firebase setup instructions for your platforms
   - Add your `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)

4. Deploy Cloud Functions:
   ```bash
   cd functions
   npm install
   npm run build
   firebase deploy --only functions
   ```

5. Configure Firestore TTL policies (required for security):
   ```bash
   # Set TTL policies for automatic cleanup
   # message_nonces: 1 hour
   # message_tokens: 1 hour
   # message_rate_limits: 2 hours
   # message_sequences: 30 days
   ```

6. Run the app:
   ```bash
   flutter run
   ```

## How to Use Security Features

### Viewing Your Security Code
1. Open the app and navigate to the **Profile** tab
2. Tap **Security Code**
3. View your fingerprint and QR code
4. Share with conversation partners to verify encryption

### Verifying a Conversation Partner
1. Meet in person, on a video call, or voice call
2. Both users open their **Security Code** screen
3. Compare the codes - they should match exactly
4. If codes match, your conversation is secure ✓

### Rotating Encryption Keys
1. Go to **Profile** → **Rotate Encryption Keys**
2. Confirm the action
3. New keys generated and old keys archived automatically
4. All previous messages remain readable
5. Share your new security code with partners

### Managing Linked Devices
1. Go to **Profile** → **Linked Devices**
2. View all connected devices
3. Link new devices via QR code scanning
4. Remove compromised devices

### Recovery Phrase Backup
1. During signup, you'll receive a 12-word recovery phrase
2. Write it down and store it securely offline
3. This phrase can recover your account and encryption keys
4. Never share it with anyone - not even us

## Development Status

This project is currently in active development.

### Implemented Features
- ✅ User authentication (email/password, Google Sign-In)
- ✅ Two-factor authentication (TOTP + backup codes)
- ✅ BIP39 recovery phrase generation and verification
- ✅ End-to-end encryption (AES-256-GCM, ECDH, HKDF)
- ✅ GCM authentication tag validation
- ✅ Binary key encoding with format versioning
- ✅ Public key fingerprint verification
- ✅ Key rotation with backward compatibility
- ✅ Replay attack protection (sequence numbers + nonce tracking)
- ✅ Rate limiting (global + per-conversation with soft blocking)
- ✅ Device linking and management
- ✅ Secure key storage with versioning
- ✅ Message encryption key version tracking
- ✅ Messaging interface with conversation view
- ✅ Media sharing (images, videos) with encryption
- ✅ GIF integration via Giphy
- ✅ Link previews for shared URLs
- ✅ Typing indicators
- ✅ Read receipts and delivery status
- ✅ Offline message queue
- ✅ Screenshot protection
- ✅ Partner linking via invite codes

### In Progress
- 🚧 Voice messages
- 🚧 Gift ideas tracker
- 🚧 Date planning features
- 🚧 Shared experiences tracking

## Cloud Functions

The following server-side functions handle security-critical operations:

| Function | Purpose |
|----------|---------|
| `enable2FA` | Generate TOTP secret and backup codes |
| `verify2FATOTP` | Server-side TOTP validation with rate limiting |
| `verify2FABackupCode` | Validate and consume backup codes |
| `disable2FA` | Remove 2FA from account |
| `regenerateBackupCodes` | Generate new backup codes |
| `validateMessageSend` | Message validation, rate limiting, replay protection |
| `acceptPartnerInvite` | Partner linking and key exchange |

## Security Configuration

### Rate Limits
| Resource | Limit |
|----------|-------|
| Messages (global) | 30/min, 500/hour |
| Messages (per-conversation) | 20/min, 300/hour |
| TOTP attempts | 5 per 5 minutes |
| Backup code attempts | 3 per 5 minutes |

### Cryptographic Parameters
| Parameter | Value |
|-----------|-------|
| Encryption | AES-256-GCM |
| Key Exchange | ECDH secp256k1 |
| TOTP Secret | 256 bits |
| Recovery Phrase | 128 bits (12 words) |
| PBKDF2 Iterations | 100,000 (2FA), 2,048 (seed) |

## Privacy & Security

Echo Protocol is built with privacy as a fundamental principle. All data is encrypted and stored securely, accessible only to the authenticated partners. We never share, sell, or access your personal conversations or data.

## License

This project is licensed under the Business Source License 1.1 (BSL-1.1).
- **Non-production use allowed immediately**
- **Commercial use prohibited until December 26, 2029**
- **On that date, the license automatically reverts to AGPLv3+**

See [LICENSE](LICENSE) for full terms.

## Contributing

This is a personal project created as a gift. Contributions are not currently being accepted.

---

Built with love, for love.
