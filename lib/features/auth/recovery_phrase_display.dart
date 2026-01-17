import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/secure_storage.dart';
import 'recovery_phrase_verify.dart';

class RecoveryPhraseDisplayScreen extends StatefulWidget {
  final String recoveryPhrase;
  final void Function(BuildContext context) onComplete;

  const RecoveryPhraseDisplayScreen({
    super.key,
    required this.recoveryPhrase,
    required this.onComplete,
  });

  @override
  State<RecoveryPhraseDisplayScreen> createState() => _RecoveryPhraseDisplayScreenState();
}

class _RecoveryPhraseDisplayScreenState extends State<RecoveryPhraseDisplayScreen> {
  final SecureStorageService _secureStorage = SecureStorageService();
  bool _hasSaved = false;
  bool _showPhrase = false;

  List<String> get _words => widget.recoveryPhrase.split(' ');

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: widget.recoveryPhrase));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Recovery phrase copied. Will auto-clear in 60 seconds.'),
        duration: Duration(seconds: 3),
      ),
    );
    Future.delayed(const Duration(seconds: 60), () {
      Clipboard.setData(const ClipboardData(text: ''));
    });
  }

  Future<void> _proceedToVerification() async {
    final verified = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecoveryPhraseVerifyScreen(
          recoveryPhrase: widget.recoveryPhrase,
        ),
      ),
    );

    if (verified == true && mounted) {
      await _secureStorage.clearPendingRecoveryPhrase();
      if (mounted) {
        widget.onComplete(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Recovery Phrase'),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.amber.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Write down these 12 words in order. They are the ONLY way to recover your account.',
                        style: TextStyle(color: Colors.amber.shade900),
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
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Your Recovery Phrase',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                _showPhrase ? Icons.visibility_off : Icons.visibility,
                                size: 20,
                              ),
                              onPressed: () => setState(() => _showPhrase = !_showPhrase),
                              tooltip: _showPhrase ? 'Hide' : 'Show',
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 20),
                              onPressed: _copyToClipboard,
                              tooltip: 'Copy',
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_showPhrase) ...[
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 3.5,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: _words.length,
                        itemBuilder: (context, index) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 24,
                                child: Text(
                                  '${index + 1}.',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  _words[index],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontFamily: 'monospace',
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      Container(
                        height: 150,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_outline, size: 40, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text(
                              'Tap the eye icon to reveal your recovery phrase',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Important',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Never share your recovery phrase with anyone\n'
                      '• Store it in a secure location offline\n'
                      '• If you lose this phrase, you cannot recover your messages\n'
                      '• We cannot recover your phrase for you',
                      style: TextStyle(
                        color: Colors.red.shade900,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              CheckboxListTile(
                value: _hasSaved,
                onChanged: (value) => setState(() => _hasSaved = value ?? false),
                title: const Text('I have written down my recovery phrase'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _hasSaved ? _proceedToVerification : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
