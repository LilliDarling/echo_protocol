import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/auth.dart';
import '../settings/fingerprint_verification.dart';
import '../settings/device_linking.dart';

class ProfileTab extends StatelessWidget {
  final AuthService _authService = AuthService();

  ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;

    return ListView(
      children: [
        // User Info Header
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).primaryColor,
                Theme.of(context).primaryColor.withValues(alpha: 0.7),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundColor: Colors.white,
                child: Text(
                  user?.displayName?[0].toUpperCase() ?? 'U',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                user?.displayName ?? 'User',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                user?.email ?? '',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Security Section
        _buildSectionHeader(context, 'Security'),

        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.verified_user,
              color: Colors.blue.shade700,
            ),
          ),
          title: const Text('Security Code'),
          subtitle: const Text('View your fingerprint for verification'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FingerprintVerificationScreen(
                  userId: user!.uid,
                ),
              ),
            );
          },
        ),

        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.devices,
              color: Colors.purple.shade700,
            ),
          ),
          title: const Text('Linked Devices'),
          subtitle: const Text('Manage your connected devices'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DeviceLinkingScreen(
                  userId: user!.uid,
                ),
              ),
            );
          },
        ),

        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.vpn_key,
              color: Colors.green.shade700,
            ),
          ),
          title: const Text('Rotate Encryption Keys'),
          subtitle: const Text('Generate new encryption keys'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showKeyRotationDialog(context),
        ),

        const Divider(height: 32),

        // Account Section
        _buildSectionHeader(context, 'Account'),

        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.person_outline,
              color: Colors.grey,
            ),
          ),
          title: const Text('Edit Profile'),
          subtitle: const Text('Update your name and photo'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            // TODO: Implement profile editing
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Coming soon!')),
            );
          },
        ),

        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.settings,
              color: Colors.grey,
            ),
          ),
          title: const Text('Preferences'),
          subtitle: const Text('Theme, notifications, auto-delete'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            // TODO: Implement preferences
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Coming soon!')),
            );
          },
        ),

        const Divider(height: 32),

        // Legal Section
        _buildSectionHeader(context, 'Legal'),

        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.privacy_tip,
              color: Colors.indigo.shade700,
            ),
          ),
          title: const Text('Privacy Policy'),
          subtitle: const Text('How we handle your data'),
          trailing: const Icon(Icons.open_in_new, size: 20),
          onTap: () => _launchPrivacyPolicy(context),
        ),

        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.description,
              color: Colors.teal.shade700,
            ),
          ),
          title: const Text('Terms of Service'),
          subtitle: const Text('Usage terms and conditions'),
          trailing: const Icon(Icons.open_in_new, size: 20),
          onTap: () => _launchTermsOfService(context),
        ),

        const SizedBox(height: 32),

        // About Section
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Text(
                'Echo Protocol',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Secure End-to-End Encrypted Messaging',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock, size: 14, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Text(
                    'secp256k1 • AES-256-GCM • HKDF-SHA256',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade400,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  static const String _privacyPolicyUrl = 'https://www.notion.so/Echo-Protocol-Privacy-Policy-2c6041b919bf80aa9e33e0a30e127b5c';
  static const String _termsOfServiceUrl = 'https://yourwebsite.com/terms-of-service';

  Future<void> _launchPrivacyPolicy(BuildContext context) async {
    final uri = Uri.parse(_privacyPolicyUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Privacy Policy')),
      );
    }
  }

  Future<void> _launchTermsOfService(BuildContext context) async {
    final uri = Uri.parse(_termsOfServiceUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Terms of Service')),
      );
    }
  }

  Future<void> _showKeyRotationDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rotate Encryption Keys?'),
        content: const Text(
          'This will generate new encryption keys for your account.\n\n'
          '⚠️ WARNING: This will invalidate all existing encrypted conversations. '
          'Only do this if you suspect your keys may be compromised.\n\n'
          'Your conversation partners will need to re-verify your security code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('Rotate Keys'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await _performKeyRotation(context);
    }
  }

  Future<void> _performKeyRotation(BuildContext context) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Rotating encryption keys...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final result = await _authService.rotateEncryptionKeys();

      if (context.mounted) {
        Navigator.pop(context); // Close loading dialog

        // Show success with new fingerprint
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Keys Rotated Successfully'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your encryption keys have been updated.\n\n'
                  'New security code:',
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    result['fingerprint']!,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FingerprintVerificationScreen(
                        userId: _authService.currentUserId!,
                      ),
                    ),
                  );
                },
                child: const Text('View Security Code'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Close loading dialog

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to rotate keys: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
