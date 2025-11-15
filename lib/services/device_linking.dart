import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'secure_storage.dart';
import 'logger.dart';

class DeviceLinkingService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final SecureStorageService _secureStorage = SecureStorageService();

  /// Generate QR code data for device linking
  /// This creates a temporary secure token that the new device will use
  /// to authenticate and receive the encrypted private key
  Future<DeviceLinkData> generateLinkQRCode(String userId) async {
    final random = Random.secure();
    final tokenBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final linkToken = base64Url.encode(tokenBytes).replaceAll('=', '');

    final sessionKeyBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final sessionKey = base64Url.encode(sessionKeyBytes).replaceAll('=', '');

    final privateKey = await _secureStorage.getPrivateKey();
    if (privateKey == null) {
      throw Exception('No private key found on this device');
    }

    final publicKey = await _secureStorage.getPublicKey();
    if (publicKey == null) {
      throw Exception('No public key found on this device');
    }

    // Using AES-256-GCM for authenticated encryption (prevents tampering)
    final key = encrypt.Key.fromBase64(sessionKey + '=' * (4 - sessionKey.length % 4));
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.gcm),
    );

    final encryptedPrivateKey = encrypter.encrypt(privateKey, iv: iv);

    final expiresAt = DateTime.now().add(const Duration(minutes: 5));
    await _db.collection('deviceLinking').doc(linkToken).set({
      'userId': userId,
      'sessionKey': sessionKey,
      'encryptedPrivateKey': encryptedPrivateKey.base64,
      'publicKey': publicKey,
      'iv': iv.base64,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'used': false,
      'initiatingDeviceId': await _getDeviceId(),
    });

    // QR code contains: linking token
    // New device will use this to fetch encrypted key from Firestore
    final qrData = jsonEncode({
      'type': 'echo_protocol_device_link',
      'version': 1,
      'token': linkToken,
      'userId': userId,
      'expires': expiresAt.millisecondsSinceEpoch,
    });

    return DeviceLinkData(
      qrCodeData: qrData,
      linkToken: linkToken,
      expiresAt: expiresAt,
    );
  }

  /// Link new device by scanning QR code
  /// This retrieves and decrypts the private key from the linking session
  Future<bool> linkDeviceFromQRCode(String qrData) async {
    try {
      final data = jsonDecode(qrData) as Map<String, dynamic>;

      if (data['type'] != 'echo_protocol_device_link') {
        throw Exception('Invalid QR code type');
      }

      if (data['version'] != 1) {
        throw Exception('Unsupported QR code version');
      }

      final linkToken = data['token'] as String;
      final userId = data['userId'] as String;
      final expiresTimestamp = data['expires'] as int;

      if (DateTime.now().millisecondsSinceEpoch > expiresTimestamp) {
        throw Exception('QR code has expired');
      }

      final linkDoc = await _db.collection('deviceLinking').doc(linkToken).get();

      if (!linkDoc.exists) {
        throw Exception('Invalid or expired link token');
      }

      final linkData = linkDoc.data()!;

      if (linkData['used'] == true) {
        throw Exception('This link has already been used');
      }

      final expiresAt = (linkData['expiresAt'] as Timestamp).toDate();
      if (DateTime.now().isAfter(expiresAt)) {
        throw Exception('Link has expired');
      }

      final sessionKey = linkData['sessionKey'] as String;
      final encryptedPrivateKey = linkData['encryptedPrivateKey'] as String;
      final publicKey = linkData['publicKey'] as String;
      final ivBase64 = linkData['iv'] as String;

      // Decrypt private key using session key with AES-256-GCM
      // GCM mode provides authentication - will throw if data was tampered with
      final key = encrypt.Key.fromBase64(sessionKey + '=' * (4 - sessionKey.length % 4));
      final iv = encrypt.IV.fromBase64(ivBase64);
      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.gcm),
      );

      final encrypted = encrypt.Encrypted.fromBase64(encryptedPrivateKey);
      final privateKey = encrypter.decrypt(encrypted, iv: iv);

      await _secureStorage.storePrivateKey(privateKey);
      await _secureStorage.storePublicKey(publicKey);
      await _secureStorage.storeUserId(userId);

      await _db.collection('deviceLinking').doc(linkToken).update({
        'used': true,
        'usedAt': FieldValue.serverTimestamp(),
        'linkedDeviceId': await _getDeviceId(),
      });

      await _addLinkedDevice(userId);

      Future.delayed(const Duration(minutes: 1), () {
        _db.collection('deviceLinking').doc(linkToken).delete();
      });

      await _logDeviceLink(userId, linkToken);

      return true;
    } catch (e) {
      LoggerService.error('Device linking failed');
      return false;
    }
  }

  Future<void> cancelDeviceLink(String linkToken) async {
    await _db.collection('deviceLinking').doc(linkToken).delete();
  }

  Future<List<LinkedDevice>> getLinkedDevices(String userId) async {
    final userDoc = await _db.collection('users').doc(userId).get();
    final devicesData = userDoc.data()?['linkedDevices'] as List? ?? [];

    return devicesData.map((device) {
      return LinkedDevice.fromJson(device as Map<String, dynamic>);
    }).toList();
  }

  /// Remove a linked device
  /// WARNING: If removed device was the only one with the key, messages become unreadable
  Future<void> removeLinkedDevice(String userId, String deviceId) async {
    final currentDeviceId = await _getDeviceId();

    if (deviceId == currentDeviceId) {
      throw Exception('Cannot remove current device');
    }

    final userDoc = await _db.collection('users').doc(userId).get();
    final devicesData = userDoc.data()?['linkedDevices'] as List? ?? [];

    final updatedDevices = devicesData.where((device) {
      return (device as Map<String, dynamic>)['deviceId'] != deviceId;
    }).toList();

    await _db.collection('users').doc(userId).update({
      'linkedDevices': updatedDevices,
    });

    await _logDeviceRemoval(userId, deviceId);
  }

  // Private helper methods
  
  Future<String> _getDeviceId() async {
    var deviceId = await _secureStorage.getDeviceId();

    if (deviceId == null) {
      final random = Random.secure();
      final bytes = List<int>.generate(16, (_) => random.nextInt(256));
      deviceId = base64Url.encode(bytes).replaceAll('=', '');
      await _secureStorage.storeDeviceId(deviceId);
    }

    return deviceId;
  }

  Future<void> _addLinkedDevice(String userId) async {
    final deviceId = await _getDeviceId();
    final deviceInfo = {
      'deviceId': deviceId,
      'deviceName': await _getDeviceName(),
      'linkedAt': FieldValue.serverTimestamp(),
      'lastActive': FieldValue.serverTimestamp(),
      'platform': await _getPlatform(),
    };

    await _db.collection('users').doc(userId).update({
      'linkedDevices': FieldValue.arrayUnion([deviceInfo]),
    });
  }

  Future<String> _getDeviceName() async {
    final deviceInfo = DeviceInfoPlugin();

    try {
      if (kIsWeb) {
        final webInfo = await deviceInfo.webBrowserInfo;
        return '${webInfo.browserName} on ${webInfo.platform}';
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return '${androidInfo.brand} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return '${iosInfo.name} (${iosInfo.model})';
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        return macInfo.computerName;
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        return windowsInfo.computerName;
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        return linuxInfo.name;
      }
    } catch (e) {
      LoggerService.warning('Failed to get device name');
    }

    return 'Unknown Device';
  }

  Future<String> _getPlatform() async {
    if (kIsWeb) {
      return 'Web';
    } else if (Platform.isAndroid) {
      return 'Android';
    } else if (Platform.isIOS) {
      return 'iOS';
    } else if (Platform.isMacOS) {
      return 'macOS';
    } else if (Platform.isWindows) {
      return 'Windows';
    } else if (Platform.isLinux) {
      return 'Linux';
    }

    return 'Unknown';
  }

  Future<void> _logDeviceLink(String userId, String linkToken) async {
    await _db.collection('securityLog').add({
      'userId': userId,
      'event': 'device_linked',
      'linkToken': linkToken,
      'deviceId': await _getDeviceId(),
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _logDeviceRemoval(String userId, String deviceId) async {
    await _db.collection('securityLog').add({
      'userId': userId,
      'event': 'device_removed',
      'removedDeviceId': deviceId,
      'removedBy': await _getDeviceId(),
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> cleanupExpiredLinks() async {
    final now = Timestamp.now();
    final expiredLinks = await _db
        .collection('deviceLinking')
        .where('expiresAt', isLessThan: now)
        .get();

    for (var doc in expiredLinks.docs) {
      await doc.reference.delete();
    }
  }
}

class DeviceLinkData {
  final String qrCodeData;
  final String linkToken;
  final DateTime expiresAt;

  DeviceLinkData({
    required this.qrCodeData,
    required this.linkToken,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Duration get timeRemaining => expiresAt.difference(DateTime.now());
}

class LinkedDevice {
  final String deviceId;
  final String deviceName;
  final DateTime linkedAt;
  final DateTime lastActive;
  final String platform;

  LinkedDevice({
    required this.deviceId,
    required this.deviceName,
    required this.linkedAt,
    required this.lastActive,
    required this.platform,
  });

  factory LinkedDevice.fromJson(Map<String, dynamic> json) {
    return LinkedDevice(
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
      linkedAt: (json['linkedAt'] as Timestamp).toDate(),
      lastActive: (json['lastActive'] as Timestamp).toDate(),
      platform: json['platform'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'linkedAt': Timestamp.fromDate(linkedAt),
      'lastActive': Timestamp.fromDate(lastActive),
      'platform': platform,
    };
  }

  bool get isRecentlyActive {
    final daysSinceActive = DateTime.now().difference(lastActive).inDays;
    return daysSinceActive < 30;
  }
}
