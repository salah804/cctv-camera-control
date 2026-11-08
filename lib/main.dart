
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'home.dart';
import 'login.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Camera Control',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor:
        const Color(0xFF080D18),
      ),

      // Instead of always opening LoginScreen,
      // check whether the user is already logged in.
      home: const AuthGate(),
    );
  }
}

// ========================================
// AUTHENTICATION STATUS
// ========================================

enum AuthStatus {
  checking,
  authenticated,
  unauthenticated,
  connectionError,
}

// ========================================
// AUTOMATIC LOGIN SCREEN
// ========================================

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  static const Color bg = Color(0xFF080D18);
  static const Color cyan = Color(0xFF50D5F5);
  static const Color muted = Color(0xFF94A8C2);

  // Current Cloudflare HTTPS URL.
  // Update this whenever the temporary
  // Cloudflare tunnel address changes.



  static const String checkSessionUrl =
  String.fromEnvironment(
    'CCTV_CHECK_SESSION_URL',
    defaultValue:
    'https://salahayash.helioho.st/cctv-api/check_session.php',
  );



  final FlutterSecureStorage _secureStorage =
  const FlutterSecureStorage();

  AuthStatus _status = AuthStatus.checking;

  @override
  void initState() {
    super.initState();
    _checkSavedSession();
  }

  // ========================================
  // CHECK SAVED LOGIN SESSION
  // ========================================

  Future<void> _checkSavedSession() async {
    if (!mounted) return;

    setState(() {
      _status = AuthStatus.checking;
    });

    try {
      // STEP 1: Read the saved PHP session token.
      final String? sessionToken =
      await _secureStorage.read(
        key: 'session_token',
      );

      if (sessionToken == null ||
          sessionToken.isEmpty) {
        debugPrint(
          'No saved Google session found.',
        );

        _updateStatus(
          AuthStatus.unauthenticated,
        );

        return;
      }

      debugPrint(
        'Saved session found. Verifying...',
      );

      // STEP 2: Check the HTTPS endpoint.
      final Uri? endpoint =
      Uri.tryParse(checkSessionUrl);

      if (endpoint == null ||
          endpoint.scheme != 'https' ||
          endpoint.host.isEmpty) {
        _updateStatus(
          AuthStatus.connectionError,
        );

        return;
      }

      // STEP 3: Ask PHP to validate the token.
      final http.Response response =
      await http
          .get(
        endpoint,
        headers: {
          'Accept': 'application/json',
          'Authorization':
          'Bearer $sessionToken',
        },
      )
          .timeout(
        const Duration(seconds: 15),
      );

      // Only log the HTTP status.
      // Never print authentication tokens.
      debugPrint(
        'Session verification HTTP status: '
            '${response.statusCode}',
      );

      // STEP 4: Handle expired / invalid tokens.
      if (response.statusCode == 401 ||
          response.statusCode == 403) {
        debugPrint(
          'Saved session expired or invalid.',
        );

        await _clearSavedSession();

        _updateStatus(
          AuthStatus.unauthenticated,
        );

        return;
      }

      // STEP 5: Handle server errors.
      if (response.statusCode != 200) {
        _updateStatus(
          AuthStatus.connectionError,
        );

        return;
      }

      // STEP 6: Read the verified user.
      final dynamic decoded =
      jsonDecode(response.body);

      if (decoded is! Map<String, dynamic> ||
          decoded['success'] != true ||
          decoded['user'] is! Map) {
        _updateStatus(
          AuthStatus.connectionError,
        );

        return;
      }

      final Map user = decoded['user'];

      final dynamic username =
      user['username'];

      if (username is! String ||
          username.isEmpty) {
        _updateStatus(
          AuthStatus.connectionError,
        );

        return;
      }

      // STEP 7: Keep existing Home and
      // Profile screens compatible.
      final SharedPreferences prefs =
      await SharedPreferences.getInstance();

      await prefs.setString(
        'username',
        username,
      );

      // STEP 8: Automatically open Home.
      debugPrint(
        'Session valid. Opening Home.',
      );

      _updateStatus(
        AuthStatus.authenticated,
      );
    } on TimeoutException {
      debugPrint(
        'Session verification timed out.',
      );

      _updateStatus(
        AuthStatus.connectionError,
      );
    } catch (e) {
      debugPrint(
        'Session verification failed: '
            '${e.runtimeType}',
      );

      _updateStatus(
        AuthStatus.connectionError,
      );
    }
  }

  // ========================================
  // CLEAR INVALID LOCAL SESSION
  // ========================================

  Future<void> _clearSavedSession() async {
    await _secureStorage.delete(
      key: 'session_token',
    );

    final SharedPreferences prefs =
    await SharedPreferences.getInstance();

    await prefs.remove('username');
  }

  // ========================================
  // UPDATE STATUS
  // ========================================

  void _updateStatus(AuthStatus status) {
    if (!mounted) return;

    setState(() {
      _status = status;
    });
  }

  // ========================================
  // SELECT START SCREEN
  // ========================================

  @override
  Widget build(BuildContext context) {
    switch (_status) {
      case AuthStatus.checking:
        return _buildLoadingScreen();

      case AuthStatus.authenticated:
        return HomeScreen();

      case AuthStatus.unauthenticated:
        return const LoginScreen();


      case AuthStatus.connectionError:
      // Do not open Home without a verified session.
      // Show normal Login if the server is unavailable.
        return const LoginScreen();

    }
  }

  // ========================================
  // LOADING SCREEN
  // ========================================

  Widget _buildLoadingScreen() {
    return const Scaffold(
      backgroundColor: bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shield_outlined,
              color: cyan,
              size: 72,
            ),

            SizedBox(height: 20),

            Text(
              'CAMERA CONTROL',
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),

            SizedBox(height: 22),

            CircularProgressIndicator(
              color: cyan,
            ),

            SizedBox(height: 16),

            Text(
              'Checking your saved session...',
              style: TextStyle(
                color: muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========================================
  // CONNECTION ERROR SCREEN
  // ========================================

  Widget _buildConnectionError() {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.wifi_off_rounded,
                  color: cyan,
                  size: 65,
                ),

                const SizedBox(height: 22),

                const Text(
                  'Connection Unavailable',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 14),

                const Text(
                  'We could not verify your saved '
                      'session. Check your internet '
                      'connection and make sure the '
                      'PHP server is running.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: muted,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 28),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _checkSavedSession,
                    icon: const Icon(
                      Icons.refresh,
                    ),
                    label: const Text(
                      'Try Again',
                    ),
                    style:
                    ElevatedButton.styleFrom(
                      backgroundColor: cyan,
                      foregroundColor: bg,
                      padding:
                      const EdgeInsets.all(16),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                TextButton(
                  onPressed: () {
                    _updateStatus(
                      AuthStatus.unauthenticated,
                    );
                  },
                  child: const Text(
                    'Go to Login / Demo',
                    style: TextStyle(
                      color: cyan,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
