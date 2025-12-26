import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/screenshot_protection.dart';
import '../../widgets/common/progress_indicator.dart';
import '../../widgets/common/custom_button.dart';
import 'onboarding_success.dart';

class BackupCodesScreen extends StatefulWidget {
  final List<String> backupCodes;
  final String userId;
  final bool isOnboarding;

  const BackupCodesScreen({
    super.key,
    required this.backupCodes,
    required this.userId,
    this.isOnboarding = false,
  });

  @override
  State<BackupCodesScreen> createState() => _BackupCodesScreenState();
}

class _BackupCodesScreenState extends State<BackupCodesScreen> {
  bool _hasAcknowledged = false;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    ScreenshotProtectionService.enableProtection();
  }

  @override
  void dispose() {
    ScreenshotProtectionService.disableProtection();
    super.dispose();
  }

  Future<void> _downloadCodes() async {
    setState(() => _isDownloading = true);

    try {
      final codesText = widget.backupCodes.asMap().entries.map((entry) {
        return '${entry.key + 1}. ${entry.value}';
      }).join('\n');

      await Clipboard.setData(ClipboardData(text: codesText));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup codes copied to clipboard')),
      );

      setState(() => _hasAcknowledged = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save backup codes')),
      );
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  void _continue() {
    if (widget.isOnboarding) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => OnboardingSuccessScreen(userId: widget.userId),
        ),
      );
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Save Your Backup Codes'),
        automaticallyImplyLeading: !widget.isOnboarding,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.isOnboarding) ...[
              const StepProgressIndicator(currentStep: 3, totalSteps: 4),
              const SizedBox(height: 24),
            ],
            const Icon(
              Icons.warning_amber_rounded,
              size: 48,
              color: Colors.orange,
            ),
            const SizedBox(height: 16),
            const Text(
              'Save Your Backup Codes',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Keep these safe! Each can be used once if you lose your authenticator device.',
              textAlign: TextAlign.center,
            ),
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
                  Icon(Icons.security, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Screenshots are blocked for your security.',
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
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.backupCodes.asMap().entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Text(
                      '${entry.key + 1}. ${entry.value}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 16,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),
            CustomButton(
              text: 'Copy to Clipboard',
              onPressed: _isDownloading ? null : _downloadCodes,
              isLoading: _isDownloading,
              icon: Icons.copy,
            ),
            const SizedBox(height: 24),
            CheckboxListTile(
              value: _hasAcknowledged,
              onChanged: (value) {
                setState(() => _hasAcknowledged = value ?? false);
              },
              title: const Text('I have securely saved these backup codes'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            CustomButton(
              text: 'Continue',
              onPressed: _hasAcknowledged ? _continue : null,
            ),
          ],
        ),
      ),
    );
  }
}
