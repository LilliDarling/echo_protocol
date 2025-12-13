# Privacy Policy for Echo Protocol

**Last Updated: December 11, 2025**

**Effective Date: December 11, 2025**

## Developer Information

**App Name**: Echo Protocol

**Developer**: [Your Name or Company Name]

**Address**: [Your Address]

**Email**: [Your Support Email]

**Website**: [Your Website URL]

## Introduction

Echo Protocol ("we," "our," or "us") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application Echo Protocol (the "App").

Please read this Privacy Policy carefully. By using the App, you agree to the collection and use of information in accordance with this policy.

## Summary of Data Practices

| Data Type | Collected | Shared | Purpose |
|-----------|-----------|--------|---------|
| Email address | Yes | No | Account authentication |
| Name | Yes | No | Profile display |
| Profile photo | Optional | No | Profile display |
| Messages | Yes (encrypted) | No | Core app functionality |
| Device info | Yes | No | Multi-device sync |
| Crash logs | No | No | N/A |
| Analytics | No | No | N/A |
| Advertising ID | No | No | N/A |
| Location | No | No | N/A |
| Contacts | No | No | N/A |

## Information We Collect

### Personal Information You Provide

When you create an account and use Echo Protocol, we collect the following information:

- **Email Address**: Required for account creation and authentication
- **Display Name**: The name you choose to display to your partner
- **Profile Photo**: Optional photo for your profile (from camera, gallery, or Google account)
- **Authentication Data**: Login credentials managed securely through Firebase Authentication
- **Google Account Information**: If you sign in with Google, we receive your email, name, and profile photo from your Google account

### Messages and Communications

- **Message Content**: All messages are end-to-end encrypted using AES-256-GCM encryption. **We cannot read your message content** as it is encrypted on your device before transmission. Only you and your partner can decrypt messages.
- **Message Metadata**: We store message timestamps, delivery status (sent, delivered, read), and sender/recipient identifiers to facilitate message delivery
- **Media Files**: Photos and videos you share can be encrypted before upload. File metadata such as timestamps and file sizes are stored to enable delivery.

### Device Information

- **Device Identifiers**: Device name, model, brand, and platform (Android/iOS) for multi-device management
- **Linked Devices**: Information about devices connected to your account for multi-device synchronization

### Cryptographic Keys

- **Public Keys**: Your public encryption keys are stored on our servers to enable end-to-end encryption with your partner
- **Private Keys**: Your private encryption keys are stored **only on your device** using secure storage mechanisms (Android EncryptedSharedPreferences, iOS Keychain) and are never transmitted to our servers in readable form

### Security Information

- **Two-Factor Authentication**: If enabled, 2FA configuration data is stored securely on our servers
- **Security Logs**: We maintain logs of security events such as device linking, key rotation, and 2FA changes for account security purposes

### Information We Do NOT Collect

- Location data or GPS coordinates
- Contact lists or address books
- Call logs or SMS messages
- Browsing history
- Advertising identifiers
- Analytics or usage tracking data
- Financial or payment information
- Health data
- Files or documents outside the app

## Legal Basis for Processing (GDPR)

We process your personal data based on the following legal grounds:

- **Contract Performance**: Processing necessary to provide the messaging service you requested
- **Legitimate Interests**: Processing for security, fraud prevention, and service improvement
- **Consent**: Where you have given explicit consent (e.g., optional profile photo)
- **Legal Obligation**: Processing required to comply with applicable laws

## How We Use Your Information

We use the information we collect to:

- **Provide Core Functionality**: Enable end-to-end encrypted messaging between you and your partner
- **Account Management**: Facilitate account creation, authentication, and profile management
- **Multi-Device Sync**: Enable you to use Echo Protocol across multiple devices
- **Message Delivery**: Process and deliver messages and media files
- **Security**: Detect, prevent, and address security threats and unauthorized access
- **Customer Support**: Respond to your support requests and inquiries
- **Legal Compliance**: Comply with applicable laws and legal obligations

We do **NOT** use your information for:
- Advertising or marketing purposes
- Selling to third parties
- Profiling or automated decision-making
- Training AI models

## Data Storage and Security

### Encryption

- **End-to-End Encryption**: All messages are encrypted using secp256k1 elliptic curve cryptography for key exchange and AES-256-GCM for message encryption
- **Secure Key Storage**: Private keys are stored using platform-specific secure storage with hardware-backed encryption when available
- **Media Encryption**: Optional encryption available for photos and videos using AES-256-GCM
- **Transport Security**: All data in transit is protected using TLS/SSL

### Data Storage Locations

- **User Data**: Stored using Google Firebase Cloud Firestore (servers in the United States)
- **Media Files**: Stored using Google Firebase Cloud Storage (servers in the United States)
- **Local Data**: Sensitive credentials stored locally on your device using encrypted storage

### Data Retention

- **Account Data**: Retained until you delete your account
- **Messages**: May be automatically deleted based on your preferences (configurable, default: 30 days)
- **Security Logs**: Retained for up to 90 days for security purposes
- **Deleted Content**: When you delete messages, they are marked as deleted and permanently removed within 30 days

## Third-Party Services

We use the following third-party services to operate the App. These services may process your data according to their own privacy policies:

### Firebase (Google LLC)

- **Firebase Authentication**: User authentication and account management
- **Cloud Firestore**: Secure database for user data and encrypted messages
- **Firebase Cloud Storage**: Storage for media files
- **Firebase Cloud Functions**: Server-side processing
- **Firebase Cloud Messaging**: Push notification delivery

**Firebase Privacy Policy**: https://firebase.google.com/support/privacy

**Google Privacy Policy**: https://policies.google.com/privacy

### Google Sign-In

If you choose to sign in with Google, your authentication is processed by Google according to their privacy policy.

**Google Privacy Policy**: https://policies.google.com/privacy

## Data Sharing and Disclosure

**We do not sell, trade, or rent your personal information to third parties.**

We may share information only in these limited circumstances:

- **Service Providers**: With Firebase/Google solely for operating the App's infrastructure
- **Legal Requirements**: When required by law, court order, subpoena, or governmental authority
- **Safety**: To protect the safety, rights, or property of Echo Protocol, our users, or others
- **Business Transfers**: In connection with a merger, acquisition, or sale of assets (you will be notified)
- **With Your Consent**: When you explicitly agree to share information

## Your Rights and Choices

### Access and Portability

- View your account information directly in the App
- Request a copy of your personal data by contacting us

### Correction

- Update your profile information (name, photo) at any time in the App

### Deletion

You can delete your data in the following ways:

1. **Delete Individual Messages**: Long-press any message you sent to delete it
2. **Delete Your Account**: Go to Settings > Account > Delete Account
   - This permanently deletes your account, profile, messages, and all associated data
   - This action cannot be undone
3. **Request Deletion**: Email us at [Your Support Email] to request complete data deletion

When you delete your account:
- Your profile and account information are immediately deleted
- Your messages are deleted from our servers
- Your partner will no longer be able to see your profile
- Encrypted data on your devices must be deleted by uninstalling the app

### Device Management

- View and remove linked devices in Settings > Linked Devices
- Unlink from your partner at any time in Settings

### Notification Preferences

- Manage push notification settings in your device's system settings

## Children's Privacy

Echo Protocol is **not intended for children under the age of 13** (or 16 in the European Union).

We do not knowingly collect personal information from children. If you are a parent or guardian and believe your child has provided us with personal information, please contact us immediately at [Your Support Email] so we can delete such information.

If we discover that we have collected personal information from a child under the relevant age, we will delete that information promptly.

## International Data Transfers

Your information is transferred to and processed in the United States, where Google Firebase services are hosted. The United States may have different data protection laws than your country of residence.

By using the App, you consent to the transfer of your information to the United States. We ensure appropriate safeguards are in place for these transfers, including:

- Standard contractual clauses approved by relevant authorities
- Firebase's compliance with applicable data protection frameworks

## Changes to This Privacy Policy

We may update this Privacy Policy from time to time. When we make changes:

- We will update the "Last Updated" date at the top
- For significant changes, we will notify you through the App or via email
- Your continued use of the App after changes constitutes acceptance

We encourage you to review this Privacy Policy periodically.

## Security Measures

We implement technical and organizational measures to protect your personal information:

- **End-to-end encryption** for all message content
- **Hardware-backed secure storage** for encryption keys
- **TLS/SSL encryption** for all data in transit
- **Rate limiting** to prevent abuse
- **Replay attack protection** with cryptographic nonces
- **Security event logging** and monitoring
- **Two-factor authentication** option for account security
- **Regular security reviews** of our infrastructure

## California Privacy Rights (CCPA)

If you are a California resident, you have the following rights under the California Consumer Privacy Act:

- **Right to Know**: Request information about the personal data we collect, use, and disclose
- **Right to Delete**: Request deletion of your personal data
- **Right to Non-Discrimination**: We will not discriminate against you for exercising your rights
- **Right to Opt-Out of Sale**: We do not sell personal information

To exercise these rights, contact us at [Your Support Email].

## European Union Users (GDPR)

If you are in the European Economic Area, you have the following rights under the General Data Protection Regulation:

- **Right of Access**: Obtain confirmation of whether we process your data and access to that data
- **Right to Rectification**: Correct inaccurate personal data
- **Right to Erasure**: Request deletion of your personal data ("right to be forgotten")
- **Right to Restrict Processing**: Limit how we use your data
- **Right to Data Portability**: Receive your data in a portable format
- **Right to Object**: Object to processing based on legitimate interests
- **Right to Withdraw Consent**: Withdraw consent at any time where processing is based on consent

To exercise these rights, contact us at [Your Support Email].

You also have the right to lodge a complaint with your local data protection supervisory authority.

## Contact Us

If you have questions, concerns, or requests regarding this Privacy Policy or our data practices, please contact us:

**Email**: [Your Support Email]

**Mailing Address**: [Your Address]

**In-App Support**: Submit a support ticket through the App (Settings > Support)

We will respond to your inquiry within 30 days.

---

*This privacy policy is designed to comply with Google Play Store requirements, GDPR, CCPA, and other applicable privacy regulations. We recommend having it reviewed by a legal professional to ensure compliance with all laws applicable to your specific situation.*
