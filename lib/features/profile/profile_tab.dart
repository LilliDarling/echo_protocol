import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/auth.dart';
import '../settings/fingerprint_verification.dart';
import '../settings/device_linking.dart';
import '../settings/two_factor_settings.dart';
import '../settings/preferences.dart';
import 'edit_profile.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final AuthService _authService = AuthService();
  bool _isLinking = false;

  Future<void> _linkGoogleAccount() async {
    setState(() => _isLinking = true);

    try {
      await _authService.linkGoogleAccount();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google account linked successfully'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLinking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    final providers = _authService.getLinkedProviders();
    final hasGoogleLinked = providers.contains('google.com');

    if (user == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        final userData = snapshot.data?.data() as Map<String, dynamic>?;
        final username = userData?['username'] as String? ?? '';
        final displayName = userData?['name'] as String? ?? username;
        final avatarUrl = userData?['avatar'] as String?;

        return _buildProfileContent(
          context,
          user: user,
          username: username,
          displayName: displayName,
          avatarUrl: avatarUrl,
          hasGoogleLinked: hasGoogleLinked,
        );
      },
    );
  }

  Widget _buildProfileContent(
    BuildContext context, {
    required dynamic user,
    required String username,
    required String displayName,
    String? avatarUrl,
    required bool hasGoogleLinked,
  }) {
    return ListView(
      children: [
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
                backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                    ? NetworkImage(avatarUrl)
                    : null,
                child: avatarUrl == null || avatarUrl.isEmpty
                    ? Text(
                        displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 16),
              Text(
                displayName,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if (username.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '@$username',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 8),

        if (!hasGoogleLinked) ...[
          _buildSectionHeader(context, 'Link Account'),

          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.g_mobiledata,
                color: Colors.red.shade700,
                size: 24,
              ),
            ),
            title: const Text('Link Google Account'),
            subtitle: const Text('Enable Google as an alternative sign-in'),
            trailing: _isLinking
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _isLinking ? null : _linkGoogleAccount,
          ),

          const Divider(height: 32),
        ],

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
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.security,
              color: Colors.orange.shade700,
            ),
          ),
          title: const Text('Two-Factor Authentication'),
          subtitle: const Text('Add extra security to your account'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TwoFactorSettingsScreen(
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

        const Divider(height: 32),

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
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const EditProfileScreen(),
              ),
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
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const PreferencesScreen(),
              ),
            );
          },
        ),

        const Divider(height: 32),

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
}
