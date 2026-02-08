import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'features/auth/login.dart';
import 'features/auth/recovery_phrase_display.dart';
import 'features/auth/onboarding_success.dart';
import 'features/home/home.dart';
import 'services/auth.dart';
import 'services/crypto/protocol_service.dart';
import 'services/secure_storage.dart';
import 'services/notification.dart';
import 'services/sync/sync_coordinator.dart';
import 'core/theme/app.dart';
import 'core/providers/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (!kIsWeb) {
    await GoogleSignIn.instance.initialize();
  }

  runApp(const EchoProtocolApp());
}

class EchoProtocolApp extends StatelessWidget {
  const EchoProtocolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'Echo Protocol',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.darkTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.dark,
            home: const AuthWrapper(),
          );
        },
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final AuthService _authService = AuthService();
  final SecureStorageService _secureStorage = SecureStorageService();
  final ProtocolService _protocolService = ProtocolService();
  final NotificationService _notificationService = NotificationService();
  SyncCoordinator? _syncCoordinator;

  bool _keysLoaded = false;
  bool _isLoadingKeys = false;
  String? _pendingRecoveryPhrase;
  bool _checkedPendingPhrase = false;
  bool _notificationsInitialized = false;
  bool _syncInitialized = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          if (!_keysLoaded && !_isLoadingKeys) {
            return FutureBuilder(
              future: _loadKeysIfNeeded(),
              builder: (context, keySnapshot) {
                if (keySnapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                if (_pendingRecoveryPhrase != null) {
                  final userId = _authService.currentUserId!;
                  return RecoveryPhraseDisplayScreen(
                    recoveryPhrase: _pendingRecoveryPhrase!,
                    onComplete: (ctx) {
                      _secureStorage.clearPendingRecoveryPhrase();
                      _pendingRecoveryPhrase = null;
                      Navigator.of(ctx).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (_) => OnboardingSuccessScreen(userId: userId),
                        ),
                        (route) => false,
                      );
                    },
                  );
                }

                return const HomeScreen();
              },
            );
          }
          return const HomeScreen();
        }

        _keysLoaded = false;
        _isLoadingKeys = false;
        _pendingRecoveryPhrase = null;
        _checkedPendingPhrase = false;
        _notificationsInitialized = false;
        _syncInitialized = false;
        _syncCoordinator?.dispose();
        _syncCoordinator = null;
        _notificationService.dispose();
        Provider.of<ThemeProvider>(context, listen: false).reset();
        return const LoginScreen();
      },
    );
  }

  Future<void> _loadKeysIfNeeded() async {
    _isLoadingKeys = true;
    try {
      final hasKeys = await _secureStorage.hasEncryptionKeys();
      if (hasKeys) {
        await _protocolService.initializeFromStorage();
      }

      if (!_checkedPendingPhrase) {
        _pendingRecoveryPhrase = await _secureStorage.getPendingRecoveryPhrase();
        _checkedPendingPhrase = true;
      }

      final userId = _authService.currentUserId;
      if (userId != null && mounted) {
        final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
        await themeProvider.loadPreferences(userId);

        if (!_notificationsInitialized) {
          await _notificationService.initialize(userId);
          _notificationsInitialized = true;
        }

        if (!_syncInitialized && hasKeys) {
          _syncCoordinator = SyncCoordinator();
          await _syncCoordinator!.initialize();
          _syncInitialized = true;
        }
      }

      _keysLoaded = true;
    } catch (e) {
      _checkedPendingPhrase = true;
    } finally {
      _isLoadingKeys = false;
    }
  }
}
