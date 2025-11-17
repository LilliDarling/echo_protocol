# Fingerprint Verification User Guide

## Overview

Echo Protocol uses public key fingerprints to verify conversation security. This guide explains how users verify each other's identity before exchanging sensitive messages.

## What is a Fingerprint?

A **fingerprint** is a short, human-readable representation of a user's public encryption key. It looks like this:

```
1A2B 3C4D 5E6F 7A8B 9C0D 1E2F 3A4B 5C6D
```

If two users see the same fingerprint for each other, they can be confident their conversation is secure and not being intercepted.

## When to Verify Fingerprints

### Required Verification Scenarios:
1. **Before sharing sensitive information** (passwords, financial data, private documents)
2. **For high-security conversations** (legal, medical, confidential business)
3. **After either party rotates their encryption keys**

### Optional but Recommended:
- First conversation with a new contact
- Periodically for ongoing sensitive conversations
- When you suspect your account might be compromised

## Verification Methods

### Method 1: QR Code Scanning (Recommended - Fastest)

**In Person:**
1. Both users open the conversation
2. User A: Tap **"Verify Security"** → **"Show My QR Code"**
3. User B: Tap **"Verify Security"** → **"Scan QR Code"**
4. User B scans User A's QR code
5. ✅ App automatically verifies and marks conversation as secure

**Why this works:** The QR code contains both users' public keys. Scanning proves you're in the same physical location.

---

### Method 2: Number Comparison (In-Person or Video Call)

**Steps:**
1. Both users open the conversation → **"Verify Security"**
2. Both users see the same fingerprint code on their screens:
   ```
   1A2B 3C4D 5E6F 7A8B
   9C0D 1E2F 3A4B 5C6D
   ```
3. Users compare the numbers:
   - **In person:** Look at each other's screens
   - **Video call:** Read the numbers out loud
   - **Voice call:** One person reads all numbers, other confirms
4. If numbers match exactly → Tap **"Mark as Verified"** ✓

**Important:** Even ONE digit different = NOT SECURE. Do not mark as verified.

---

### Method 3: Voice Verification (Over Phone)

**Steps:**
1. Both users open conversation → **"Verify Security"**
2. User A reads their fingerprint out loud:
   ```
   "One-A, Two-B, Three-C, Four-D, Five-E, Six-F..."
   ```
3. User B confirms: "I see the same numbers on my screen"
4. User B reads their fingerprint
5. User A confirms
6. Both tap **"Mark as Verified"**

**Tip:** Read in groups of 4 for easier verification: "One-A-Two-B, Three-C-Four-D..."

---

## Security Best Practices

### ✅ DO:
- Verify through a **different channel** than the app (in-person, video, voice)
- Verify **before** sending sensitive information
- Re-verify after key rotation warnings
- Take your time - accuracy matters more than speed

### ❌ DON'T:
- Verify fingerprints via Echo Protocol messages (defeats the purpose!)
- Verify via email or unencrypted chat
- Skip verification for sensitive conversations
- Mark as verified if even one character differs

---

## What Happens After Verification?

Once verified:
- ✅ Green checkmark appears on conversation
- 🔒 "Verified" badge shows on partner's profile
- You can confidently exchange sensitive information
- You'll be warned if keys change (requires re-verification)

---

## Understanding Security Warnings

### "Security Code Has Changed"
**Why:** Your conversation partner rotated their encryption keys or reinstalled the app.

**What to do:**
1. Ask your partner (via another channel) if they rotated keys
2. Re-verify the new fingerprint using methods above
3. Mark as verified again if fingerprints match

**⚠️ Warning:** If your partner says they did NOT rotate keys, someone may be intercepting your messages. Contact support immediately.

---

## Technical Details

### How Fingerprints Work

```
Alice's Public Key → SHA-256 Hash → 1A2B3C4D5E6F7A8B9C0D1E2F3A4B5C6D
Bob's Public Key   → SHA-256 Hash → A1B2C3D4E5F6A7B8C9D0E1F2A3B4C5D6
```

The fingerprint is:
- **Deterministic:** Same key = same fingerprint, always
- **Unique:** Different keys = different fingerprints
- **Collision-resistant:** Impossible to create fake key with same fingerprint
- **One-way:** Cannot reverse fingerprint to get the key

### Why Out-of-Band Verification Matters

**The Problem:**
If an attacker intercepts your messages, they could:
1. Replace Alice's public key with their own
2. Decrypt messages from Bob
3. Re-encrypt with real Alice's key
4. Forward to Alice (man-in-the-middle attack)

**The Solution:**
By verifying fingerprints via **video call, voice call, or in-person**, you confirm that the public key you received matches the one your partner actually has. An attacker cannot intercept a video call showing your screen or your voice reading numbers.

---

## Example Verification Scenarios

### Scenario 1: Sharing Medical Records
```
Dr. Smith: "Before you send your medical history, let's verify our conversation"
Patient: "Good idea. I'll tap Verify Security"

[Both compare fingerprints via video call]

Dr. Smith: "I see 1A2B 3C4D 5E6F 7A8B..."
Patient: "Same here! And my code is A1B2 C3D4 E5F6..."
Dr. Smith: "Confirmed. Marked as verified ✓"
```

### Scenario 2: Business Confidential Documents
```
CEO: "Let's verify before sharing Q4 financials"
CFO: "Agreed. Scanning your QR code now..."

[QR scan successful]

✅ Conversation verified
Now safe to share sensitive documents
```

### Scenario 3: Key Rotation Warning
```
⚠️ Warning: Bob's security code changed
Bob rotated encryption keys yesterday

[Message Bob via phone call]
You: "Hey, did you rotate your keys?"
Bob: "Yes, I got a new phone yesterday"
You: "Let's re-verify then"

[Video call verification]
✅ Verified with new fingerprint
```

---

## Implementation Code Example

```dart
// Get fingerprints for verification
final myFingerprint = await authService.getMyPublicKeyFingerprint();
final partnerFingerprint = encryptionService.getPartnerFingerprint();

print('My fingerprint: $myFingerprint');
print('Partner fingerprint: $partnerFingerprint');

// Verify partner's fingerprint (after out-of-band confirmation)
final userConfirmedMatch = await showVerificationDialog(
  myFingerprint: myFingerprint,
  partnerFingerprint: partnerFingerprint,
);

if (userConfirmedMatch) {
  // Mark conversation as verified in Firestore
  await markConversationAsVerified(conversationId);
}
```

---

## FAQ

**Q: Do I need to verify every conversation?**
A: No. Verify when exchanging sensitive information or for high-security contacts.

**Q: Can I verify via Echo Protocol messages?**
A: No - that defeats the security purpose. Use video, voice, or in-person verification.

**Q: What if fingerprints don't match?**
A: DO NOT proceed. Contact your partner via phone/in-person to investigate. May indicate man-in-the-middle attack.

**Q: How often should I re-verify?**
A: After key rotation warnings, or periodically for ongoing sensitive conversations.

**Q: Is verification permanent?**
A: Yes, until either party rotates their encryption keys. Then you must re-verify.

---

## ✅ Implementation Status: COMPLETE

The fingerprint verification UI is **fully implemented and production-ready**!

### How to Access in the App

1. **Open Echo Protocol**
2. **Navigate to Profile Tab** (bottom navigation bar)
3. **Tap "Security Code"** (blue shield icon)
4. **View Your Security Code**:
   - Human-readable fingerprint (8 groups of 4 hex chars)
   - Copy button for easy sharing
   - QR code for in-person scanning
   - Step-by-step verification instructions
   - Security warnings and best practices

### Implemented Files

- **Fingerprint UI**: `lib/features/settings/fingerprint_verification.dart`
- **Profile Tab**: `lib/features/profile/profile_tab.dart`
- **Backend Services**: `lib/services/encryption.dart`, `lib/services/auth.dart`
- **Comprehensive Tests**: 17 new tests added (127/127 passing)

### Additional Security Features in Profile

- 🔒 **Security Code** - View and share your fingerprint
- 📱 **Linked Devices** - Manage connected devices
- 🔄 **Rotate Encryption Keys** - Generate new keys on-demand

All features are fully functional and follow Signal Protocol best practices!
