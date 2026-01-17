import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'features/auth/login.dart';
import 'features/home/home.dart';
import 'services/auth.dart';
import 'services/crypto/protocol_service.dart';
import 'services/secure_storage.dart';
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
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
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

  bool _keysLoaded = false;
  bool _isLoadingKeys = false;

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
                return const HomeScreen();
              },
            );
          }
          return const HomeScreen();
        }

        _keysLoaded = false;
        _isLoadingKeys = false;
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

      final userId = _authService.currentUserId;
      if (userId != null && mounted) {
        final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
        await themeProvider.loadPreferences(userId);
      }

      _keysLoaded = true;
    } catch (e) {
      // Ignore errors - the app will handle missing keys appropriately
    } finally {
      _isLoadingKeys = false;
    }
  }
}
