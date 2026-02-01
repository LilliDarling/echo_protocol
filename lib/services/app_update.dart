import 'dart:io';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdateService {
  static const String _appStoreId = 'app.echoprotocol';
  static const String _playStoreId = 'app.echoprotocol';

  static Future<void> checkForUpdate(BuildContext context) async {
    if (Platform.isAndroid) {
      await _checkAndroidUpdate(context);
    } else if (Platform.isIOS) {
      await _checkIOSUpdate(context);
    }
  }

  static Future<void> _checkAndroidUpdate(BuildContext context) async {
    try {
      final updateInfo = await InAppUpdate.checkForUpdate();

      if (updateInfo.updateAvailability == UpdateAvailability.updateAvailable) {
        if (updateInfo.immediateUpdateAllowed) {
          await InAppUpdate.performImmediateUpdate();
        } else if (updateInfo.flexibleUpdateAllowed) {
          await InAppUpdate.startFlexibleUpdate();
          await InAppUpdate.completeFlexibleUpdate();
        } else {
          if (context.mounted) {
            _showUpdateDialog(context, isAndroid: true);
          }
        }
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
  }

  static Future<void> _checkIOSUpdate(BuildContext context) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final storeVersion = await _getIOSStoreVersion();
      if (storeVersion != null && _isNewerVersion(storeVersion, currentVersion)) {
        if (context.mounted) {
          _showUpdateDialog(context, isAndroid: false);
        }
      }
    } catch (e) {
      debugPrint('iOS update check failed: $e');
    }
  }

  static Future<String?> _getIOSStoreVersion() async {
    try {
      final uri = Uri.parse('https://itunes.apple.com/lookup?bundleId=$_appStoreId');
      final response = await HttpClient().getUrl(uri).then((req) => req.close());

      if (response.statusCode == 200) {
        final body = await response.transform(const SystemEncoding().decoder).join();
        final versionMatch = RegExp(r'"version"\s*:\s*"([^"]+)"').firstMatch(body);
        return versionMatch?.group(1);
      }
    } catch (e) {
      debugPrint('Failed to get iOS store version: $e');
    }
    return null;
  }

  static bool _isNewerVersion(String storeVersion, String currentVersion) {
    final storeParts = storeVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final currentParts = currentVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    while (storeParts.length < 3) {
      storeParts.add(0);
    }
    while (currentParts.length < 3) {
      currentParts.add(0);
    }

    for (int i = 0; i < 3; i++) {
      if (storeParts[i] > currentParts[i]) return true;
      if (storeParts[i] < currentParts[i]) return false;
    }
    return false;
  }

  static void _showUpdateDialog(BuildContext context, {required bool isAndroid}) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.system_update, color: Colors.blue),
            SizedBox(width: 12),
            Text('Update Available'),
          ],
        ),
        content: const Text(
          'A new version of Echo Protocol is available. Update now for the latest features and improvements.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _openStore(isAndroid);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  static Future<void> _openStore(bool isAndroid) async {
    final Uri uri;
    if (isAndroid) {
      uri = Uri.parse('https://play.google.com/store/apps/details?id=$_playStoreId');
    } else {
      uri = Uri.parse('https://apps.apple.com/app/id$_appStoreId');
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
