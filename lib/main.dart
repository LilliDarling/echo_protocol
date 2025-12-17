import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'features/auth/login.dart';
import 'features/home/home.dart';
import 'services/auth.dart';
import 'services/encryption.dart';
import 'services/secure_storage.dart';
import 'core/theme/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const EchoProtocolApp());
}

class EchoProtocolApp extends StatelessWidget {
  const EchoProtocolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Echo Protocol',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const AuthWrapper(),
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
  final EncryptionService _encryptionService = EncryptionService();

  bool _keysLoaded = false;

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
          // User is authenticated - try to load keys if not already loaded
          if (!_keysLoaded) {
            _loadKeysIfNeeded();
          }
          return const HomeScreen();
        }

        // Reset key loading state on logout
        _keysLoaded = false;
        return const LoginScreen();
      },
    );
  }

  Future<void> _loadKeysIfNeeded() async {
    try {
      final hasKeys = await _secureStorage.hasEncryptionKeys();
      if (hasKeys) {
        final privateKey = await _secureStorage.getPrivateKey();
        final keyVersion = await _secureStorage.getCurrentKeyVersion();
        if (privateKey != null) {
          _encryptionService.setPrivateKey(privateKey, keyVersion: keyVersion);
        }
      }
      _keysLoaded = true;
    } catch (e) {
      // Ignore errors - the app will handle missing keys appropriately
    }
  }
}
