import 'dart:typed_data';
import 'package:bip39/bip39.dart' as bip39;
import 'package:pointycastle/export.dart';
import 'package:crypto/crypto.dart';

/// Service for BIP39 mnemonic-based key generation and recovery.
/// Keys are deterministically derived from a 12-word recovery phrase.
class RecoveryPhraseService {
  static const int _mnemonicStrength = 128; // 12 words
  static const String _salt = 'echo-protocol-v1';
  static const int _pbkdf2Iterations = 2048;

  /// Generate a new 12-word recovery phrase.
  String generateMnemonic() {
    return bip39.generateMnemonic(strength: _mnemonicStrength);
  }

  /// Validate a recovery phrase.
  bool validateMnemonic(String mnemonic) {
    return bip39.validateMnemonic(mnemonic.trim().toLowerCase());
  }

  /// Get the list of words from a mnemonic.
  List<String> getWords(String mnemonic) {
    return mnemonic.trim().toLowerCase().split(' ');
  }

  /// Derive a seed from the mnemonic for key generation.
  Uint8List deriveSeedFromMnemonic(String mnemonic) {
    if (!validateMnemonic(mnemonic)) {
      throw Exception('Invalid recovery phrase');
    }

    final normalizedMnemonic = mnemonic.trim().toLowerCase();

    // Use PBKDF2 with SHA-512 as per BIP39 spec
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA512Digest(), 128))
      ..init(Pbkdf2Parameters(
        Uint8List.fromList(_salt.codeUnits),
        _pbkdf2Iterations,
        64, // 512 bits
      ));

    final mnemonicBytes = Uint8List.fromList(normalizedMnemonic.codeUnits);
    final seed = Uint8List(64);
    pbkdf2.deriveKey(mnemonicBytes, 0, seed, 0);

    return seed;
  }

  /// Generate a deterministic key version from the public key.
  int deriveKeyVersion(String publicKey) {
    final hash = sha256.convert(publicKey.codeUnits);
    final bytes = hash.bytes.sublist(0, 4);
    return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  }
}
