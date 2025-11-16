import 'package:flutter/material.dart';
import '../../services/two_factor.dart';
import '../../widgets/code_input.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_field.dart';
import '../home/home.dart';
import 'account_recovery.dart';

class TwoFactorVerifyScreen extends StatefulWidget {
  final String userId;

  const TwoFactorVerifyScreen({
    super.key,
    required this.userId,
  });

  @override
  State<TwoFactorVerifyScreen> createState() => _TwoFactorVerifyScreenState();
}

class _TwoFactorVerifyScreenState extends State<TwoFactorVerifyScreen> {
  final TwoFactorService _twoFactorService = TwoFactorService();
  final TextEditingController _backupCodeController = TextEditingController();

  bool _isVerifying = false;
  bool _useBackupCode = false;
  String _error = '';
  String _totpCode = '';

  @override
  void dispose() {
    _backupCodeController.dispose();
    super.dispose();
  }

  Future<void> _verifyTOTP() async {
    if (_totpCode.length != 6) return;

    setState(() {
      _isVerifying = true;
      _error = '';
    });

    try {
      final isValid = await _twoFactorService.verifyTOTP(_totpCode, userId: widget.userId);

      if (isValid) {
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      } else {
        setState(() {
          _error = 'Invalid code. Please try again.';
          _isVerifying = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString().contains('2FA not set up')
            ? 'Please use a backup code or contact support.'
            : 'Verification failed. Please try again.';
        _isVerifying = false;
      });
    }
  }

  Future<void> _verifyBackupCode() async {
    final code = _backupCodeController.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _isVerifying = true;
      _error = '';
    });

    try {
      final isValid = await _twoFactorService.verifyBackupCode(code, widget.userId);

      if (isValid) {
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      } else {
        setState(() {
          _error = 'Invalid backup code.';
          _isVerifying = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Verification failed. Please try again.';
        _isVerifying = false;
      });
    }
  }

  void _showRecovery() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AccountRecoveryScreen(userId: widget.userId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Two-Factor Authentication'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_useBackupCode) ...[
              const Text(
                'Enter Authentication Code',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Open your authenticator app and enter the 6-digit code for Echo Protocol.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              CodeInput(
                onCompleted: (code) {
                  setState(() => _totpCode = code);
                },
                onChanged: (code) {
                  setState(() => _totpCode = code);
                },
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  _error,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              CustomButton(
                text: 'Verify',
                onPressed: _totpCode.length == 6 && !_isVerifying ? _verifyTOTP : null,
                isLoading: _isVerifying,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  setState(() {
                    _useBackupCode = true;
                    _error = '';
                  });
                },
                child: const Text('Use backup code instead'),
              ),
            ] else ...[
              const Text(
                'Use Backup Code',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Enter one of your saved backup codes:',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              CustomTextField(
                controller: _backupCodeController,
                label: 'Backup Code',
                hint: 'XXXX-XXXX',
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Note: Each backup code can only be used once.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  _error,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              CustomButton(
                text: 'Verify',
                onPressed: _backupCodeController.text.isNotEmpty && !_isVerifying
                    ? _verifyBackupCode
                    : null,
                isLoading: _isVerifying,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  setState(() {
                    _useBackupCode = false;
                    _error = '';
                    _backupCodeController.clear();
                  });
                },
                child: const Text('Back to TOTP code'),
              ),
            ],
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'Lost access to your account?',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _showRecovery,
              child: const Text('Get Help'),
            ),
          ],
        ),
      ),
    );
  }
}
