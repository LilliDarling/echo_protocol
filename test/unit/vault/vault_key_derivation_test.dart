import 'dart:convert';
import 'dart:typed_data';
import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';
import 'package:echo_protocol/models/crypto/identity_key.dart';
import 'package:echo_protocol/utils/security.dart';

void main() {
  group('Vault Key Derivation', () {
    late Uint8List seed;

    setUp(() {
      final mnemonic = bip39.generateMnemonic(strength: 128);
      seed = Uint8List.fromList(bip39.mnemonicToSeed(mnemonic));
    });

    test('derives a 32-byte vault key', () {
      final vaultKey = IdentityKeyPair.deriveVaultKey(seed);
      expect(vaultKey.length, 32);
    });

    test('derivation is deterministic', () {
      final key1 = IdentityKeyPair.deriveVaultKey(seed);
      final key2 = IdentityKeyPair.deriveVaultKey(seed);
      expect(
        SecurityUtils.constantTimeBytesEquals(key1, key2),
        isTrue,
      );
    });

    test('different seeds produce different keys', () {
      final otherMnemonic = bip39.generateMnemonic(strength: 128);
      final otherSeed =
          Uint8List.fromList(bip39.mnemonicToSeed(otherMnemonic));

      final key1 = IdentityKeyPair.deriveVaultKey(seed);
      final key2 = IdentityKeyPair.deriveVaultKey(otherSeed);

      expect(
        SecurityUtils.constantTimeBytesEquals(key1, key2),
        isFalse,
      );
    });

    test('vault key is domain-separated from identity keys', () {
      final vaultKey = IdentityKeyPair.deriveVaultKey(seed);

      // Derive the same keys that _deriveFromMasterSeed uses
      final ed25519Seed = SecurityUtils.hkdfSha256(
        seed,
        Uint8List.fromList(utf8.encode('EchoProtocol-Identity-v1')),
        Uint8List.fromList(utf8.encode('ed25519-signing-key')),
        32,
      );
      final x25519Seed = SecurityUtils.hkdfSha256(
        seed,
        Uint8List.fromList(utf8.encode('EchoProtocol-Identity-v1')),
        Uint8List.fromList(utf8.encode('x25519-agreement-key')),
        32,
      );

      expect(
        SecurityUtils.constantTimeBytesEquals(vaultKey, ed25519Seed),
        isFalse,
      );
      expect(
        SecurityUtils.constantTimeBytesEquals(vaultKey, x25519Seed),
        isFalse,
      );
    });

    test('vault key can be base64 encoded and decoded', () {
      final vaultKey = IdentityKeyPair.deriveVaultKey(seed);
      final encoded = base64Encode(vaultKey);
      final decoded = base64Decode(encoded);

      expect(
        SecurityUtils.constantTimeBytesEquals(
          Uint8List.fromList(decoded),
          vaultKey,
        ),
        isTrue,
      );
    });

    test('same recovery phrase always produces same vault key', () {
      const phrase =
          'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      final seed1 = Uint8List.fromList(bip39.mnemonicToSeed(phrase));
      final seed2 = Uint8List.fromList(bip39.mnemonicToSeed(phrase));

      final key1 = IdentityKeyPair.deriveVaultKey(seed1);
      final key2 = IdentityKeyPair.deriveVaultKey(seed2);

      expect(
        SecurityUtils.constantTimeBytesEquals(key1, key2),
        isTrue,
      );
    });
  });
}
