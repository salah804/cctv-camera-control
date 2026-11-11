
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'home.dart';
import 'register.dart';
import 'demo_screen.dart';
import 'google_button.dart';
import 'package:camera/forgot%20password.dart';

// ==========================================
// CCTV CAMERA CONTROL
// LOGIN SCREEN - ANDROID + WEB
// ==========================================

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // ========================================
  // THEME COLORS
  // ========================================

  static const Color bg = Color(0xFF080D18);
  static const Color surface = Color(0xFF111C2D);
  static const Color border = Color(0xFF26364B);
  static const Color cyan = Color(0xFF50D5F5);
  static const Color muted = Color(0xFF94A8C2);
  static const Color green = Color(0xFF4ADE80);

  // ========================================
  // PHP BACKEND
  // ========================================

  static const String loginUrl =
      'https://salahayash.helioho.st/cctv-api/login.php';

  static const String googleLoginUrl =
      'https://salahayash.helioho.st/cctv-api/google_login.php';

  // Existing Web OAuth Client ID.
  // Android uses this as serverClientId.
  // Web reads its client ID from web/index.html.

  static const String googleWebClientId =
      '628625399302-8orvhe3gidkdvfs7kt4lc8h5g0994qa2.apps.googleusercontent.com';

  // ========================================
  // FORM CONTROLLERS
  // ========================================

  final GlobalKey<FormState> _formKey =
  GlobalKey<FormState>();

  final TextEditingController _usernameController =
  TextEditingController();

  final TextEditingController _passwordController =
  TextEditingController();

  final FlutterSecureStorage _secureStorage =
  const FlutterSecureStorage();

  // ========================================
  // GOOGLE SIGN-IN
  // ========================================

  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: kIsWeb ? null : googleWebClientId,
    scopes: const [
      'email',
      'profile',
    ],
  );

  StreamSubscription<GoogleSignInAccount?>?
  _googleUserSubscription;

  bool _busy = false;
  bool _hidePassword = true;

  @override
  void initState() {
    super.initState();

    // Flutter Web:
    // Google's official button emits account changes.
    // We use that account to obtain a verified ID token.

    if (kIsWeb) {
      _googleUserSubscription =
          _googleSignIn.onCurrentUserChanged.listen(
                (GoogleSignInAccount? account) {
              if (account != null && mounted) {
                _processGoogleAccount(account);
              }
            },
            onError: (Object error) {
              debugPrint(
                'Google Web event failed: ${error.runtimeType}',
              );

              if (mounted) {
                _showMessage(
                  'Google authentication failed. Please try again.',
                );
              }
            },
          );
    }
  }

  // ========================================
  // CLEANUP
  // ========================================

  @override
  void dispose() {
    _googleUserSubscription?.cancel();

    _usernameController.dispose();
    _passwordController.dispose();

    super.dispose();
  }

  // ========================================
  // NOTIFICATIONS
  // ========================================

  void _showMessage(
      String message, {
        bool error = true,
      }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error
              ? const Color(0xFFAD3545)
              : const Color(0xFF176B54),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  bool _isSuccess(dynamic data) {
    return data is Map &&
        (data['success'] == true ||
            data['success'] == 1 ||
            data['success'] == 'true');
  }

  String _serverMessage(
      dynamic data,
      String fallback,
      ) {
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }

    return fallback;
  }

  // ========================================
  // HTTPS VALIDATION
  // ========================================

  Uri? _httpsEndpoint(String url) {
    final uri = Uri.tryParse(url.trim());

    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty) {
      return null;
    }

    return uri;
  }

  // ========================================
  // SAVE AUTHENTICATED SESSION
  // ========================================

  Future<void> _saveAuthenticatedSession({
    required Map<String, dynamic> responseData,
    required String authMethod,
  }) async {
    final user = responseData['user'];
    final token = responseData['session_token'];

    if (user is! Map ||
        user['username'] is! String ||
        token is! String ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(token)) {
      throw const FormatException(
        'Missing authenticated session.',
      );
    }

    final username =
    (user['username'] as String).trim();

    if (username.isEmpty) {
      throw const FormatException(
        'Missing account username.',
      );
    }

    // Keep server session handling unchanged.
    await _secureStorage.write(
      key: 'session_token',
      value: token,
    );

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'username',
      username,
    );

    await prefs.setString(
      'auth_method',
      authMethod,
    );
  }

  // ========================================
  // NAVIGATION
  // ========================================

  void _openHome() {
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const HomeScreen(),
      ),
    );
  }

  void _openRegister() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const RegisterPage(),
      ),
    );
  }

  void _openForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ForgotPasswordPage(),
      ),
    );
  }

  void _openDemo() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const DemoScreen(),
      ),
    );
  }

  // ========================================
  // REGULAR USERNAME / PASSWORD LOGIN
  // ========================================

  Future<void> _login() async {
    if (_busy) return;

    if (_formKey.currentState?.validate() != true) {
      return;
    }

    final endpoint = _httpsEndpoint(loginUrl);

    if (endpoint == null) {
      _showMessage(
        'Login HTTPS backend is not configured.',
      );
      return;
    }

    FocusScope.of(context).unfocus();

    final username =
    _usernameController.text.trim();

    final password = _passwordController.text;

    setState(() {
      _busy = true;
    });

    try {
      final response = await http.post(
        endpoint,
        headers: {
          'Accept': 'application/json',
        },
        body: {
          'username': username,
          'password': password,
        },
      ).timeout(
        const Duration(seconds: 20),
      );

      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes),
      );

      if (!mounted) return;

      if (response.statusCode != 200 ||
          !_isSuccess(decoded)) {
        _showMessage(
          _serverMessage(
            decoded,
            'Invalid username or password.',
          ),
        );
        return;
      }

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'Invalid server response.',
        );
      }

      await _saveAuthenticatedSession(
        responseData: decoded,
        authMethod: 'password',
      );

      _passwordController.clear();

      if (!mounted) return;

      _openHome();
    } on TimeoutException {
      _showMessage(
        'Login timed out. Check your connection.',
      );
    } on FormatException {
      _showMessage(
        'Invalid authentication response from PHP.',
      );
    } catch (e) {
      debugPrint(
        'Regular login failed: ${e.runtimeType}',
      );

      _showMessage(
        'Cannot complete login. Check the PHP server.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  // ========================================
  // GOOGLE SIGN-IN - ANDROID
  // ========================================

  Future<void> _signInWithGoogle() async {
    if (kIsWeb || _busy) return;

    try {
      // Preserve Android's existing sign-in flow.
      final GoogleSignInAccount? account =
      await _googleSignIn.signIn();

      if (account == null) return;

      await _processGoogleAccount(account);
    } catch (e) {
      debugPrint(
        'Android Google Sign-In failed: ${e.runtimeType}',
      );

      _showMessage(
        'Google Sign-In failed. '
            'Check your connection and try again.',
      );
    }
  }

  // ========================================
  // GOOGLE SIGN-IN - ANDROID + WEB
  // ========================================

  Future<void> _processGoogleAccount(
      GoogleSignInAccount account,
      ) async {
    if (!mounted || _busy) return;

    final endpoint = _httpsEndpoint(
      googleLoginUrl,
    );

    if (endpoint == null) {
      _showMessage(
        'Google HTTPS backend is not configured.',
      );
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      // Android:
      // Account comes from GoogleSignIn.signIn().
      //
      // Web:
      // Account comes from the official Google
      // Sign-In button and its account event.

      final authentication =
      await account.authentication;

      final String? idToken =
          authentication.idToken;

      if (idToken == null || idToken.isEmpty) {
        _showMessage(
          'Google did not return an ID token. '
              'Check your Google OAuth configuration.',
        );
        return;
      }

      // PHP verifies the Google ID token
      // and returns the app's own session token.

      final response = await http.post(
        endpoint,
        headers: {
          'Accept': 'application/json',
        },
        body: {
          'id_token': idToken,
        },
      ).timeout(
        const Duration(seconds: 20),
      );

      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes),
      );

      if (!mounted) return;

      if (response.statusCode != 200 ||
          !_isSuccess(decoded)) {
        _showMessage(
          _serverMessage(
            decoded,
            'Google Sign-In failed.',
          ),
        );
        return;
      }

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'Invalid Google authentication response.',
        );
      }

      await _saveAuthenticatedSession(
        responseData: decoded,
        authMethod: 'google',
      );

      if (!mounted) return;

      _openHome();
    } on TimeoutException {
      _showMessage(
        'Google Login timed out.',
      );
    } on FormatException {
      _showMessage(
        'Invalid Google authentication response.',
      );
    } catch (e) {
      debugPrint(
        'Google authentication failed: ${e.runtimeType}',
      );

      _showMessage(
        'Google authentication could not be completed.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  // ========================================
  // INPUT FIELD DESIGN
  // ========================================

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: muted,
      ),
      prefixIcon: Icon(
        icon,
        color: cyan,
      ),
      suffixIcon: suffix,
      filled: true,
      fillColor: bg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: border,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: cyan,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: Colors.redAccent,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: Colors.redAccent,
        ),
      ),
    );
  }

  // ========================================
  // GOOGLE LOGIN BUTTON
  // ========================================

  Widget _googleLoginButton() {
    if (kIsWeb) {
      // The web plugin provides Google's actual
      // Sign-In button. A custom Flutter button
      // cannot replace this authentication flow.

      return Center(
        child: SizedBox(
          width: 280,
          height: 52,
          child: buildGoogleWebButton(),
        ),
      );
    }

    // Android button remains unchanged.
    return SizedBox(
      width: double.infinity,
      height: 53,
      child: OutlinedButton.icon(
        onPressed:
        _busy ? null : _signInWithGoogle,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: bg,
          side: const BorderSide(
            color: border,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
        icon: const Text(
          'G',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        label: const Text(
          'Continue with Google',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // ========================================
  // MAIN LOGIN SCREEN
  // ========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 480,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                20, 32, 20, 28,
              ),
              child: Column(
                children: [
                  // APPLICATION LOGO
                  Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      color: const Color(0xFF15364B),
                      borderRadius:
                      BorderRadius.circular(23),
                      border: Border.all(
                        color: cyan,
                      ),
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: cyan,
                      size: 43,
                    ),
                  ),

                  const SizedBox(height: 19),

                  const Text(
                    'CAMERA CONTROL',
                    style: TextStyle(
                      color: cyan,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Secure Monitoring Platform',
                    style: TextStyle(color: muted),
                  ),

                  const SizedBox(height: 29),

                  // LOGIN CARD
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius:
                      BorderRadius.circular(22),
                      border: Border.all(
                        color: border,
                      ),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Welcome Back',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                            ),
                          ),

                          const SizedBox(height: 8),

                          const Text(
                            'Sign in to manage your cameras '
                                'and recordings.',
                            style: TextStyle(
                              color: muted,
                              height: 1.5,
                            ),
                          ),

                          const SizedBox(height: 23),

                          // USERNAME
                          TextFormField(
                            controller:
                            _usernameController,
                            enabled: !_busy,
                            textInputAction:
                            TextInputAction.next,
                            style: const TextStyle(
                              color: Colors.white,
                            ),
                            decoration: _inputDecoration(
                              label: 'Username',
                              icon: Icons.person_outline,
                            ),
                            validator: (value) {
                              if (value == null ||
                                  value.trim().isEmpty) {
                                return 'Enter your username';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 16),

                          // PASSWORD
                          TextFormField(
                            controller:
                            _passwordController,
                            enabled: !_busy,
                            obscureText: _hidePassword,
                            textInputAction:
                            TextInputAction.done,
                            onFieldSubmitted: (_) =>
                                _login(),
                            style: const TextStyle(
                              color: Colors.white,
                            ),
                            decoration: _inputDecoration(
                              label: 'Password',
                              icon: Icons.lock_outline,
                              suffix: IconButton(
                                onPressed: _busy
                                    ? null
                                    : () {
                                  setState(() {
                                    _hidePassword =
                                    !_hidePassword;
                                  });
                                },
                                icon: Icon(
                                  _hidePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: muted,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (value == null ||
                                  value.isEmpty) {
                                return 'Enter your password';
                              }
                              return null;
                            },
                          ),

                          // FORGOT PASSWORD
                          Align(
                            alignment:
                            Alignment.centerRight,
                            child: TextButton(
                              onPressed: _busy
                                  ? null
                                  : _openForgotPassword,
                              child: const Text(
                                'Forgot Password?',
                                style: TextStyle(
                                  color: cyan,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // REGULAR SIGN IN
                          SizedBox(
                            width: double.infinity,
                            height: 53,
                            child: ElevatedButton(
                              onPressed:
                              _busy ? null : _login,
                              style:
                              ElevatedButton.styleFrom(
                                backgroundColor: cyan,
                                foregroundColor: bg,
                                shape:
                                RoundedRectangleBorder(
                                  borderRadius:
                                  BorderRadius.circular(13),
                                ),
                              ),
                              child: _busy
                                  ? const SizedBox(
                                width: 23,
                                height: 23,
                                child:
                                CircularProgressIndicator(
                                  color: bg,
                                  strokeWidth: 2.5,
                                ),
                              )
                                  : const Text(
                                'Sign In',
                                style: TextStyle(
                                  fontWeight:
                                  FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 17),

                          // REGISTER ACCOUNT
                          Row(
                            mainAxisAlignment:
                            MainAxisAlignment.center,
                            children: [
                              const Flexible(
                                child: Text(
                                  "Don't have an account?",
                                  style: TextStyle(
                                    color: muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : _openRegister,
                                child: const Text(
                                  'Create Account',
                                  style: TextStyle(
                                    color: cyan,
                                    fontWeight:
                                    FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 13),

                          // GOOGLE LOGIN DIVIDER
                          const Row(
                            children: [
                              Expanded(
                                child: Divider(
                                  color: border,
                                ),
                              ),
                              Padding(
                                padding:
                                EdgeInsets.symmetric(
                                  horizontal: 11,
                                ),
                                child: Text(
                                  'OR CONTINUE WITH',
                                  style: TextStyle(
                                    color: muted,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                  color: border,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 18),

                          // GOOGLE BUTTON
                          _googleLoginButton(),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 19),

                  // =================================
                  // CCTV DEMO MODE
                  // =================================

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius:
                      BorderRadius.circular(19),
                      border: Border.all(
                        color: cyan,
                      ),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.play_circle_outline,
                          color: green,
                          size: 30,
                        ),

                        const SizedBox(height: 9),

                        const Text(
                          'Explore CCTV Demo Mode',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),

                        const SizedBox(height: 9),

                        const Text(
                          'Try offline camera monitoring '
                              'and simulated recording playback '
                              'without signing in.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: muted,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),

                        const SizedBox(height: 15),

                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed:
                            _busy ? null : _openDemo,
                            icon: const Icon(
                              Icons.smart_display_outlined,
                            ),
                            label: const Text(
                              'Try Demo Without Login',
                            ),
                            style:
                            OutlinedButton.styleFrom(
                              foregroundColor: cyan,
                              side: const BorderSide(
                                color: cyan,
                              ),
                              padding:
                              const EdgeInsets.all(15),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 25),

                  const Text(
                    'CAMERA CONTROL CENTER',
                    style: TextStyle(
                      color: muted,
                      fontSize: 10,
                      letterSpacing: 1.5,
                    ),
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
