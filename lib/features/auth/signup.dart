import 'package:flutter/material.dart';
import '../../services/auth.dart';
import '../../utils/validators.dart';
import '../../widgets/inputs/custom_text_field.dart';
import '../../widgets/common/custom_button.dart';
import 'recovery_phrase_display.dart';
import 'onboarding_success.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != _passwordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final result = await _authService.signUpWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        displayName: _displayNameController.text.trim(),
      );

      if (mounted) {
        // Show recovery phrase screen first, then proceed to onboarding success
        final userId = result.credential.user!.uid;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => RecoveryPhraseDisplayScreen(
              recoveryPhrase: result.recoveryPhrase,
              onComplete: (ctx) {
                // Clear the entire stack and go to onboarding success
                Navigator.of(ctx).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => OnboardingSuccessScreen(userId: userId),
                  ),
                  (route) => false,
                );
              },
            ),
          ),
        );
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
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signUpWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      final result = await _authService.signInWithGoogle();

      if (mounted) {
        if (result is SignUpResult) {
          // New user - show recovery phrase first
          final userId = result.credential.user!.uid;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => RecoveryPhraseDisplayScreen(
                recoveryPhrase: result.recoveryPhrase,
                onComplete: (ctx) {
                  // Clear the entire stack and go to onboarding success
                  Navigator.of(ctx).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => OnboardingSuccessScreen(userId: userId),
                    ),
                    (route) => false,
                  );
                },
              ),
            ),
          );
        } else if (result is SignInResult) {
          // Existing user - go to onboarding success
          final userId = result.credential.user!.uid;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => OnboardingSuccessScreen(userId: userId),
            ),
          );
        }
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
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Icon
                  const Icon(
                    Icons.favorite,
                    size: 80,
                    color: Colors.pink,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Join Echo Protocol',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create your private space',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Display name field
                  CustomTextField(
                    controller: _displayNameController,
                    label: 'Name',
                    hint: 'Your name',
                    validator: (value) => Validators.validateRequired(value, 'Name'),
                    prefixIcon: const Icon(Icons.person),
                  ),
                  const SizedBox(height: 16),

                  // Email field
                  CustomTextField(
                    controller: _emailController,
                    label: 'Email',
                    hint: 'your@email.com',
                    keyboardType: TextInputType.emailAddress,
                    validator: Validators.validateEmail,
                    prefixIcon: const Icon(Icons.email),
                  ),
                  const SizedBox(height: 16),

                  // Password field
                  CustomTextField(
                    controller: _passwordController,
                    label: 'Password',
                    hint: 'At least 6 characters',
                    obscureText: _obscurePassword,
                    validator: Validators.validatePassword,
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Confirm password field
                  CustomTextField(
                    controller: _confirmPasswordController,
                    label: 'Confirm Password',
                    hint: 'Re-enter your password',
                    obscureText: _obscureConfirmPassword,
                    validator: _validateConfirmPassword,
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Sign up button
                  CustomButton(
                    text: 'Create Account',
                    onPressed: _signUp,
                    isLoading: _isLoading,
                  ),
                  const SizedBox(height: 16),

                  // Divider
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey[400])),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'OR',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.grey[400])),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Google Sign-Up button
                  SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _signUpWithGoogle,
                      icon: const Icon(Icons.g_mobiledata, size: 28),
                      label: const Text('Continue with Google'),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Privacy notice
                  Text(
                    'By signing up, your messages will be end-to-end encrypted and completely private between you and your partner.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
