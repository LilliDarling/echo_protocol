# Echo Protocol

A private, secure communication app designed for couples to stay connected, share moments, and cherish their relationship - no matter the distance.

## Overview

Echo Protocol is a Flutter-based mobile application that provides a dedicated, intimate space for partners to communicate and connect. More than just a messaging app, it's a relationship companion that helps couples share their thoughts, feelings, and memories in creative ways while keeping track of the experiences they want to share together.

## Features

### Communication
- **Private Messaging**: Send secure, encrypted messages exclusively between you and your partner
- **GIF Sharing**: Express yourself with animated messages
- **Floating Lanterns**: Send beautiful visual gestures that float across your partner's screen
- **Multiple Expression Methods**: Various creative ways to let your partner know you're thinking of them

### Shared Planning
- **Gift Ideas Tracker**: Keep track of gift ideas for your partner without them seeing
- **Date Ideas Collection**: Build a shared collection of date ideas to try together
- **Shared Experiences**: Track activities you've done together and things you want to do in the future

### Security & Privacy
- **End-to-End Encryption**: Military-grade AES-256-GCM encryption for all messages and files
- **Authentication Tag Verification**: Explicit validation of GCM authentication tags prevents tampering
- **Enhanced Key Encoding**: Binary key format with versioning and comprehensive validation
- **Public Key Fingerprint Verification**: Verify conversation partners via QR codes or security codes
- **Key Rotation with Backward Compatibility**: Rotate encryption keys without losing access to old messages
- **Two-Factor Authentication**: TOTP-based 2FA with backup codes
- **Device Management**: Link multiple devices with encrypted private key transfer
- **Secure Storage**: Platform-specific secure storage (iOS Keychain, Android KeyStore)
- **Zero-Knowledge Architecture**: Server cannot read your encrypted messages
- **No Third-Party Access**: Your conversations and data are yours alone

See [SECURITY.md](docs/SECURITY.md) for complete security architecture details.

## Technology Stack

- **Framework**: Flutter (Dart)
- **Backend**: Firebase
  - Firebase Authentication
  - Cloud Firestore (Database)
  - Firebase Storage
  - Firebase Cloud Messaging (Push notifications)
- **Platforms**: iOS, Android, Windows (with Flutter's cross-platform support)

## Getting Started

### Prerequisites
- Flutter SDK (^3.9.2)
- Dart SDK
- Firebase account
- iOS/Android development environment (Xcode/Android Studio)

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

4. Run the app:
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

## Development Status

This project is currently in active development. Core features are being implemented to create a meaningful connection tool for couples.

### Implemented Features
- ✅ User authentication (email/password, Google Sign-In)
- ✅ Two-factor authentication (TOTP)
- ✅ End-to-end encryption (AES-256-GCM, ECDH, HKDF)
- ✅ GCM authentication tag validation
- ✅ Binary key encoding with format versioning
- ✅ Public key fingerprint verification
- ✅ Key rotation with backward compatibility
- ✅ Device linking and management
- ✅ Secure key storage with versioning
- ✅ Message encryption key version tracking

### In Progress
- 🚧 Messaging interface
- 🚧 Media sharing
- 🚧 Gift ideas tracker
- 🚧 Date planning features

## Privacy & Security

Echo Protocol is built with privacy as a fundamental principle. All data is encrypted and stored securely, accessible only to the authenticated partners. We never share, sell, or access your personal conversations or data.

## License

Private project - Not for public distribution

## Contributing

This is a personal project created as a gift. Contributions are not currently being accepted.

---

Built with love, for love.
