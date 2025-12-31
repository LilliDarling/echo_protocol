# Echo Protocol - Security Layers Explained

## Complete Security Stack

### Layer 1: Two-Factor Authentication (2FA)
**Protects**: Account Access

```
Login Attempt:
├─ Username/Email ✓
├─ Password ✓
└─ 6-Digit TOTP Code from Authenticator App ✓
   └─ Changes every 30 seconds
```

**What This Stops**:
- ✅ Password leaks from other sites
- ✅ Someone guessing your password
- ✅ Phishing attacks
- ✅ Database breaches

**Attack Scenario Blocked**:
```
❌ Attacker: "I have their password!"
✓  System: "Great. Now show me the 6-digit code from their phone."
❌ Attacker: "I don't have their phone..."
✓  System: "No access then."
```

---

### Layer 2: X3DH + Double Ratchet Encryption
**Protects**: Message Content with Forward & Future Secrecy

```
Session Establishment (X3DH):
Your Device ──► Fetch Partner's Prekey Bundle
    │
    ├─► 4 Diffie-Hellman Operations
    │
    └─► Derive Root Key + Chain Key

Ongoing Messages (Double Ratchet):
Each Message ──► New Key Derived
    │
    ├─► DH Ratchet (new keys per exchange)
    │
    └─► Chain Ratchet (new key per message)
```

**What This Stops**:
- ✅ Network interception (man-in-the-middle)
- ✅ Database hacks (encrypted gibberish)
- ✅ Past message decryption (forward secrecy)
- ✅ Future message decryption after key recovery (future secrecy)
- ✅ Message replay attacks

**Attack Scenario Blocked**:
```
❌ Hacker: "I got their encryption keys!"
✓  System: "Those keys only work for that one message."
❌ Hacker: "What about past messages?"
✓  System: "Different keys, already deleted."
❌ Hacker: "Future messages?"
✓  System: "New keys generated on next exchange."
```

---

### Layer 3: Device-Only Private Keys
**Protects**: Decryption Capability

```
Private Keys:
├─ Generated on YOUR device only
├─ Stored in iOS Keychain / Android KeyStore
├─ NEVER transmitted to server
└─ NEVER synced to cloud
```

**What This Stops**:
- ✅ Server-side decryption
- ✅ Cloud backup leaks
- ✅ Remote key theft

**Attack Scenario Blocked**:
```
❌ Attacker: "I got into Firebase, give me the decryption keys!"
✓  Server: "I don't have them. They're on user devices."
❌ Attacker: "I got a backup from iCloud!"
✓  System: "Private keys aren't in backups."
```

---

### Layer 4: Transport Security (TLS/HTTPS)
**Protects**: Data in Transit

```
Your App ←[HTTPS/TLS]→ Firebase
   ↑                      ↑
Double encryption:    Server can't
E2EE + TLS           read E2EE data
```

**What This Stops**:
- ✅ WiFi packet sniffing
- ✅ ISP monitoring
- ✅ Public WiFi attacks

---

## Combined Defense Example

**Scenario**: Someone wants to read your messages to your partner

### They need to defeat ALL of these:

1. **Get your password** (defeat 2FA layer 1)
   - AND get your authenticator device
   - OR guess/phish your 2FA codes

2. **Access the encrypted messages** (defeat Double Ratchet layer 2)
   - Somehow get into Firebase
   - Download encrypted gibberish
   - Each message encrypted with different key

3. **Get your private key** (defeat device security layer 3)
   - Physically compromise your device
   - Break iOS Keychain or Android KeyStore
   - Even then, only current messages at risk (forward secrecy)

4. **Intercept network traffic** (defeat TLS layer 4)
   - Break TLS encryption
   - Still can't read Double Ratchet encrypted content

**Result**: Near impossible without physical device access + knowing your password + having your authenticator. Even with key compromise, past messages remain protected.

---

## What Each Layer Protects Against

| Threat | 2FA | Double Ratchet | Device Keys | TLS |
|--------|-----|----------------|-------------|-----|
| Stolen Password | ✅ | - | - | - |
| Database Breach | ✅ | ✅ | ✅ | - |
| Network Sniffing | - | ✅ | - | ✅ |
| Server Access | - | ✅ | ✅ | - |
| Man-in-Middle | - | ✅ | - | ✅ |
| Cloud Backup Leak | - | - | ✅ | - |
| Key Compromise (Past) | - | ✅ | - | - |
| Key Compromise (Future) | - | ✅ | - | - |
| Physical Device | ⚠️ | ⚠️ | ⚠️ | - |

⚠️ = Vulnerable if device is unlocked and compromised

---

## The One Weakness: Compromised Device

**If someone has physical access to your UNLOCKED device**:
- They can open the app (if no app-lock)
- They can see decrypted messages
- They can extract keys from memory

**Mitigations**:
1. Strong device PIN/password/biometric
2. App-level biometric lock (future)
3. Auto-lock on inactivity (future)
4. Screenshot detection (future)
5. Self-destructing messages (future)

---

## Thoughts: Maximum Security Setup

### Essential:
✅ **Enable 2FA** - Blocks password-based attacks
✅ **Store backup codes safely** - Account recovery
✅ **Use strong device PIN** - Last line of defense
✅ **Enable auto-delete (30 days)** - Limits exposure

### Optional (Extra Paranoid):
- Single device only (no key linking)
- Shorter auto-delete (7 days)
- Enable app biometric lock when implemented
- Verify partner's key fingerprint in person
- Regularly check security audit logs

### Balanced (Convenient + Secure):
- Enable 2FA with backup codes
- Link devices via QR code when needed
- Auto-delete after 30 days
- Trust device security

---

## Security Level Comparison

```
Basic (No 2FA):
Password ──────────────────► Access
                              └─► Double Ratchet Encrypted Messages
Risk: Medium

With 2FA:
Password + Phone ──────────► Access
                              └─► Double Ratchet Encrypted Messages
Risk: Low

With 2FA + Single Device:
Password + Phone ──────────► Access
                              └─► Double Ratchet (device-only keys)
                                  └─► Per-message forward secrecy
Risk: Very Low (but lose messages if device lost)

With 2FA + Biometric App Lock:
Password + Phone ──────────► Access
            └─► Biometric ──► Open App
                              └─► Double Ratchet Encrypted Messages
Risk: Very Low
```

---

## What This Does

This app provides:
- **Double Ratchet encryption** with per-message keys
- **Forward secrecy** - past messages stay safe even if keys leak
- **Future secrecy** - key compromise heals automatically
- **X3DH key exchange** for secure session setup
- **Zero-knowledge** server architecture

Each message gets its own key, and those keys are deleted after use. Even if someone got hold of one, they'd only get that single message.
