import 'package:flutter/material.dart';
import '../../services/two_factor.dart';
import '../../widgets/common/custom_button.dart';
import '../auth/two_factor_setup.dart';
import '../auth/backup_codes.dart';

class TwoFactorSettingsScreen extends StatefulWidget {
  final String userId;

  const TwoFactorSettingsScreen({
    super.key,
    required this.userId,
  });

  @override
  State<TwoFactorSettingsScreen> createState() => _TwoFactorSettingsScreenState();
}

class _TwoFactorSettingsScreenState extends State<TwoFactorSettingsScreen> {
  final TwoFactorService _twoFactorService = TwoFactorService();
  bool _isLoading = true;
  bool _is2FAEnabled = false;

  @override
  void initState() {
    super.initState();
    _load2FAStatus();
  }

  Future<void> _load2FAStatus() async {
    setState(() => _isLoading = true);
    try {
      final enabled = await _twoFactorService.is2FAEnabled(widget.userId);
      setState(() {
        _is2FAEnabled = enabled;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _enable2FA() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => TwoFactorSetupScreen(
          userId: widget.userId,
          isOnboarding: false,
        ),
      ),
    );

    if (result == true || mounted) {
      _load2FAStatus();
    }
  }

  Future<void> _disable2FA() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disable Two-Factor Authentication?'),
        content: const Text(
          'This will make your account less secure. '
          'You will only need your password to sign in.\n\n'
          'Are you sure you want to disable 2FA?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Disable'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final code = await _showCodeVerificationDialog();
    if (code == null) return;

    try {
      await _twoFactorService.disable2FA(widget.userId, code);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Two-factor authentication disabled')),
        );
        _load2FAStatus();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to disable 2FA: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String?> _showCodeVerificationDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verify Your Identity'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter your authenticator code to confirm:'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                letterSpacing: 8,
                fontWeight: FontWeight.bold,
              ),
              decoration: const InputDecoration(
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.length == 6) {
                Navigator.pop(context, controller.text);
              }
            },
            child: const Text('Verify'),
          ),
        ],
      ),
    );
  }

  Future<void> _regenerateBackupCodes() async {
    final code = await _showCodeVerificationDialog();
    if (code == null) return;

    try {
      final newCodes = await _twoFactorService.regenerateBackupCodes(widget.userId, code);
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BackupCodesScreen(
              backupCodes: newCodes,
              userId: widget.userId,
              isOnboarding: false,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to regenerate codes: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Two-Factor Authentication'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _is2FAEnabled ? Colors.green.shade50 : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _is2FAEnabled ? Colors.green.shade200 : Colors.orange.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _is2FAEnabled ? Icons.shield : Icons.shield_outlined,
                          size: 48,
                          color: _is2FAEnabled ? Colors.green.shade700 : Colors.orange.shade700,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _is2FAEnabled ? 'Enabled' : 'Not Enabled',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: _is2FAEnabled ? Colors.green.shade900 : Colors.orange.shade900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _is2FAEnabled
                                    ? 'Your account is protected with an authenticator app.'
                                    : 'Add an extra layer of security to your account.',
                                style: TextStyle(
                                  color: _is2FAEnabled ? Colors.green.shade700 : Colors.orange.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'What is 2FA?',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Two-factor authentication adds an extra layer of security by requiring a code from your authenticator app in addition to your password.',
                          style: TextStyle(color: Colors.blue.shade800),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  if (!_is2FAEnabled) ...[
                    CustomButton(
                      text: 'Enable Two-Factor Authentication',
                      onPressed: _enable2FA,
                      icon: Icons.security,
                    ),
                  ] else ...[
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.key, color: Colors.blue.shade700),
                      ),
                      title: const Text('Regenerate Backup Codes'),
                      subtitle: const Text('Get new backup codes if you lost the old ones'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _regenerateBackupCodes,
                    ),

                    const SizedBox(height: 16),

                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.remove_circle_outline, color: Colors.red.shade700),
                      ),
                      title: const Text('Disable Two-Factor Authentication'),
                      subtitle: const Text('Remove the extra security layer'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _disable2FA,
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
