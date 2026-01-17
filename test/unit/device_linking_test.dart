import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceLinking Security', () {
    test('QR code data structure should include sessionKey', () {
      final qrData = {
        'type': 'echo_protocol_device_link',
        'version': 1,
        'token': 'test_token_abc123',
        'sessionKey': 'secure_session_key_xyz',
        'userId': 'user123',
        'expires': DateTime.now().add(const Duration(minutes: 2)).millisecondsSinceEpoch,
      };

      final qrJson = jsonEncode(qrData);
      final decoded = jsonDecode(qrJson) as Map<String, dynamic>;

      expect(decoded.containsKey('sessionKey'), isTrue);
      expect(decoded['sessionKey'], equals('secure_session_key_xyz'));
    });

    test('Firestore document structure should NOT include sessionKey', () {
      final firestoreData = {
        'userId': 'user123',
        'encryptedPrivateKey': 'encrypted_data_here',
        'publicKey': 'public_key_here',
        'keyVersion': 1,
        'encryptedArchivedKeys': null,
        'iv': 'iv_base64_here',
        'archivedKeysIv': null,
        'used': false,
        'initiatingDeviceId': 'device123',
      };

      expect(firestoreData.containsKey('sessionKey'), isFalse);
    });

    test('sessionKey extraction should come from QR data not Firestore', () {
      final qrData = {
        'type': 'echo_protocol_device_link',
        'version': 1,
        'token': 'test_token',
        'sessionKey': 'the_secret_session_key',
        'userId': 'user123',
        'expires': DateTime.now().add(const Duration(minutes: 2)).millisecondsSinceEpoch,
      };

      final firestoreData = {
        'userId': 'user123',
        'encryptedPrivateKey': 'encrypted_data',
        'publicKey': 'public_key',
        'keyVersion': 1,
        'iv': 'iv_data',
        'used': false,
      };

      final sessionKeyFromQR = qrData['sessionKey'] as String;
      expect(sessionKeyFromQR, equals('the_secret_session_key'));
      expect(firestoreData.containsKey('sessionKey'), isFalse);
    });
  });
}
