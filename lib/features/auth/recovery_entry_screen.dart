import 'package:flutter/material.dart';
import '../../services/auth.dart';

/// Screen for entering recovery phrase to restore account access.
class RecoveryEntryScreen extends StatefulWidget {
  final VoidCallback onRecovered;
  final VoidCallback? onCancel;

  const RecoveryEntryScreen({
    super.key,
    required this.onRecovered,
    this.onCancel,
  });

  @override
  State<RecoveryEntryScreen> createState() => _RecoveryEntryScreenState();
}

class _RecoveryEntryScreenState extends State<RecoveryEntryScreen> {
  final AuthService _authService = AuthService();
  final List<TextEditingController> _controllers = List.generate(12, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(12, (_) => FocusNode());

  bool _isRecovering = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  String get _mnemonic => _controllers.map((c) => c.text.trim().toLowerCase()).join(' ');

  bool get _allFieldsFilled => _controllers.every((c) => c.text.trim().isNotEmpty);

  Future<void> _recover() async {
    if (!_allFieldsFilled) {
      setState(() => _error = 'Please enter all 12 words');
      return;
    }

    setState(() {
      _isRecovering = true;
      _error = null;
    });

    try {
      await _authService.recoverWithPhrase(_mnemonic);
      widget.onRecovered();
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isRecovering = false);
      }
    }
  }

  void _onWordChanged(int index, String value) {
    // Handle paste of full phrase
    if (value.contains(' ')) {
      final words = value.trim().split(RegExp(r'\s+'));
      if (words.length >= 2) {
        // Distribute words starting from current index
        for (int i = 0; i < words.length && (index + i) < 12; i++) {
          _controllers[index + i].text = words[i];
        }
        // Move focus to next empty field or last field
        final nextEmpty = _controllers.indexWhere((c) => c.text.isEmpty);
        if (nextEmpty != -1) {
          _focusNodes[nextEmpty].requestFocus();
        } else {
          _focusNodes[11].requestFocus();
        }
        return;
      }
    }

    // Auto-advance to next field on space
    if (value.endsWith(' ') && index < 11) {
      _controllers[index].text = value.trim();
      _focusNodes[index + 1].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recover Account'),
        leading: widget.onCancel != null
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: widget.onCancel,
              )
            : null,
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
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Enter your 12-word recovery phrase to restore access to your account and messages.',
                        style: TextStyle(color: Colors.blue.shade900),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Recovery Phrase',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 3.0,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: 12,
                itemBuilder: (context, index) => TextField(
                  controller: _controllers[index],
                  focusNode: _focusNodes[index],
                  decoration: InputDecoration(
                    labelText: '${index + 1}',
                    labelStyle: TextStyle(color: Colors.grey.shade500),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    isDense: true,
                  ),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                  ),
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: index < 11 ? TextInputAction.next : TextInputAction.done,
                  onChanged: (value) => _onWordChanged(index, value),
                  onSubmitted: (_) {
                    if (index < 11) {
                      _focusNodes[index + 1].requestFocus();
                    } else {
                      _recover();
                    }
                  },
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isRecovering ? null : _recover,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isRecovering
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Recover Account'),
              ),
              const SizedBox(height: 16),
              Text(
                'Tip: You can paste your entire recovery phrase into the first field.',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
