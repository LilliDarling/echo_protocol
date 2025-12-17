import 'dart:math';
import 'package:flutter/material.dart';

/// Screen to verify user has saved their recovery phrase.
/// Asks user to enter 3 random words from their phrase.
/// Returns true via Navigator.pop() when verification succeeds.
class RecoveryPhraseVerifyScreen extends StatefulWidget {
  final String recoveryPhrase;

  const RecoveryPhraseVerifyScreen({
    super.key,
    required this.recoveryPhrase,
  });

  @override
  State<RecoveryPhraseVerifyScreen> createState() => _RecoveryPhraseVerifyScreenState();
}

class _RecoveryPhraseVerifyScreenState extends State<RecoveryPhraseVerifyScreen> {
  late final List<String> _words;
  late final List<int> _verifyIndices;
  final Map<int, TextEditingController> _controllers = {};
  final Map<int, bool> _verified = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _words = widget.recoveryPhrase.split(' ');
    _verifyIndices = _generateRandomIndices();

    for (final index in _verifyIndices) {
      _controllers[index] = TextEditingController();
      _verified[index] = false;
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Generate 3 random, non-consecutive indices to verify.
  List<int> _generateRandomIndices() {
    final random = Random();
    final indices = <int>{};

    while (indices.length < 3) {
      final index = random.nextInt(12);
      // Ensure indices aren't consecutive
      if (!indices.contains(index - 1) && !indices.contains(index + 1)) {
        indices.add(index);
      }
    }

    return indices.toList()..sort();
  }

  void _verifyWord(int index) {
    final entered = _controllers[index]!.text.trim().toLowerCase();
    final expected = _words[index].toLowerCase();

    setState(() {
      _verified[index] = entered == expected;
      _error = null;
    });
  }

  bool get _allVerified => _verified.values.every((v) => v);

  void _submit() {
    // Verify all words first
    for (final index in _verifyIndices) {
      _verifyWord(index);
    }

    if (_allVerified) {
      // Pop with success result - let the display screen handle navigation
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _error = 'Some words don\'t match. Please check your recovery phrase.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Recovery Phrase'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Verify Your Recovery Phrase',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter the following words from your recovery phrase to confirm you\'ve saved it.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 32),
              ...(_verifyIndices.map((index) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Word #${index + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _controllers[index],
                      decoration: InputDecoration(
                        hintText: 'Enter word ${index + 1}',
                        border: const OutlineInputBorder(),
                        suffixIcon: _verified[index] == true
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : null,
                      ),
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: index == _verifyIndices.last
                          ? TextInputAction.done
                          : TextInputAction.next,
                      onChanged: (_) => _verifyWord(index),
                      onSubmitted: (_) {
                        if (index == _verifyIndices.last) {
                          _submit();
                        }
                      },
                    ),
                  ],
                ),
              ))),
              if (_error != null) ...[
                const SizedBox(height: 8),
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
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Verify & Continue'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
