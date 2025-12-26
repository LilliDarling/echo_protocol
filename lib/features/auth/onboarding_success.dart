import 'package:flutter/material.dart';
import '../../widgets/common/progress_indicator.dart';
import '../../widgets/common/custom_button.dart';
import '../home/home.dart';

class OnboardingSuccessScreen extends StatelessWidget {
  final String userId;

  const OnboardingSuccessScreen({
    super.key,
    required this.userId,
  });

  void _continue(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const StepProgressIndicator(currentStep: 2, totalSteps: 2),
              const SizedBox(height: 48),
              const Icon(
                Icons.check_circle_outline,
                size: 80,
                color: Colors.green,
              ),
              const SizedBox(height: 24),
              const Text(
                'All Set!',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Your account is secured with end-to-end encryption.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                "You're ready to start messaging securely!",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Tip: Enable two-factor authentication in Settings for extra security.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 48),
              CustomButton(
                text: 'Get Started',
                onPressed: () => _continue(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
