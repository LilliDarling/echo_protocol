import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../services/two_factor.dart';
import '../../utils/screenshot_protection.dart';
import '../../widgets/common/progress_indicator.dart';
import '../../widgets/inputs/code_input.dart';
import '../../widgets/common/custom_button.dart';
import 'backup_codes.dart';

class TwoFactorSetupScreen extends StatefulWidget {
  final String userId;
  final bool isOnboarding;

  const TwoFactorSetupScreen({
    super.key,
    required this.userId,
    this.isOnboarding = false,
  });

  @override
  State<TwoFactorSetupScreen> createState() => _TwoFactorSetupScreenState();
}

class _TwoFactorSetupScreenState extends State<TwoFactorSetupScreen> {
  final TwoFactorService _twoFactorService = TwoFactorService();
  TwoFactorSetup? _setup;
  bool _isLoading = true;
  bool _isVerifying = false;
  bool _showSecret = false;
  String _error = '';
  String _code = '';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    if (_showSecret) {
      ScreenshotProtectionService.disableProtection();
    }
    super.dispose();
  }

  void _toggleSecret() {
    setState(() {
      _showSecret = !_showSecret;
      if (_showSecret) {
        ScreenshotProtectionService.enableProtection();
      } else {
        ScreenshotProtectionService.disableProtection();
      }
    });
  }

  Future<void> _initialize() async {
    try {
      final setup = await _twoFactorService.enable2FA(widget.userId);
      setState(() {
        _setup = setup;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to initialize 2FA';
        _isLoading = false;
      });
    }
  }

  Future<void> _verifyCode() async {
    if (_code.length != 6) return;

    setState(() {
      _isVerifying = true;
      _error = '';
    });

    try {
      final isValid = await _twoFactorService.verifyTOTP(_code, userId: widget.userId);

      if (isValid) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => BackupCodesScreen(
              backupCodes: _setup!.backupCodes,
              userId: widget.userId,
              isOnboarding: widget.isOnboarding,
            ),
          ),
        );
      } else {
        setState(() {
          _error = 'Invalid code. Please try again.';
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

  void _copySecret() {
    if (_setup != null) {
      Clipboard.setData(ClipboardData(text: _setup!.secret));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Secret key copied to clipboard')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Secure Your Account'),
        automaticallyImplyLeading: !widget.isOnboarding,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.isOnboarding) ...[
                    const StepProgressIndicator(currentStep: 2, totalSteps: 4),
                    const SizedBox(height: 24),
                  ],
                  const Text(
                    'Scan this QR code with your authenticator app:',
                    style: TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: QrImageView(
                        data: _setup!.qrCodeData,
                        version: QrVersions.auto,
                        size: 200,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Recommended apps:',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('• Google Authenticator'),
                  const Text('• Authy'),
                  const Text('• Microsoft Authenticator'),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: _toggleSecret,
                    icon: Icon(_showSecret ? Icons.visibility_off : Icons.visibility),
                    label: Text(_showSecret ? 'Hide Manual Entry Key' : 'Show Manual Entry Key'),
                  ),
                  if (_showSecret) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Keep this key private. Anyone with access can bypass your two-factor authentication.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.red.shade900,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              _setup!.secret,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy),
                            onPressed: _copySecret,
                            tooltip: 'Copy',
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  const Text(
                    'Enter code to verify:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  CodeInput(
                    onCompleted: (code) {
                      setState(() => _code = code);
                    },
                    onChanged: (code) {
                      setState(() => _code = code);
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
                    text: 'Verify & Continue',
                    onPressed: _code.length == 6 && !_isVerifying ? _verifyCode : null,
                    isLoading: _isVerifying,
                  ),
                ],
              ),
            ),
    );
  }
}
