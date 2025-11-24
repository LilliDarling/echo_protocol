import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:base32/base32.dart';
import 'dart:math';
import 'dart:typed_data';

void main() {
  test('TOTP generation matches RFC 6238 test vectors', () {
    // RFC 6238 Test Vector
    // Secret: "12345678901234567890" (ASCII) = GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ (base32)
    final secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

    // Test vector: Time = 59 seconds should produce code 287082
    final timeWindow = 59 ~/ 30; // = 1

    final code = generateTOTPCode(secret, timeWindow);
    expect(code, '287082');
  });

  test('Current secret generation format', () {
    final random = Random.secure();
    final bytes = List<int>.generate(20, (_) => random.nextInt(256));
    final secret = base32.encode(Uint8List.fromList(bytes));

    // Should be able to decode it
    final decoded = base32.decode(secret);
    expect(decoded.length, 20);

    // Generate a code with it
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final timeWindow = now ~/ 30;
    final code = generateTOTPCode(secret, timeWindow);

    expect(code.length, 6);
  });
}

String generateTOTPCode(String secret, int timeWindow) {
  final key = base32.decode(secret);

  final timeBytes = <int>[];
  for (var i = 7; i >= 0; i--) {
    timeBytes.add((timeWindow >> (i * 8)) & 0xff);
  }

  final hmac = Hmac(sha1, key);
  final hash = hmac.convert(timeBytes).bytes;

  final offset = hash[hash.length - 1] & 0x0f;
  final binary = ((hash[offset] & 0x7f) << 24) |
      ((hash[offset + 1] & 0xff) << 16) |
      ((hash[offset + 2] & 0xff) << 8) |
      (hash[offset + 3] & 0xff);

  final code = binary % pow(10, 6).toInt();
  return code.toString().padLeft(6, '0');
}
