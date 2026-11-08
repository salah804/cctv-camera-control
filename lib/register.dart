
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'login.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  // -----------------------------------
  // APP THEME
  // -----------------------------------

  static const Color background = Color(0xFF080D18);
  static const Color surface = Color(0xFF111C2D);
  static const Color border = Color(0xFF26364B);
  static const Color cyan = Color(0xFF50D5F5);
  static const Color muted = Color(0xFF94A8C2);
  static const Color green = Color(0xFF4ADE80);

  // Replace with your current PHP server IP
  // if the laptop's IP address has changed.

  static const String registerUrl =
      'https://salahayash.helioho.st/cctv-api/Register.php';



  // -----------------------------------
  // FORM CONTROLLERS
  // -----------------------------------

  final _formKey = GlobalKey<FormState>();

  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _hidePassword = true;
  bool _hideConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_refreshPasswordStrength);
  }

  void _refreshPasswordStrength() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _passwordController.removeListener(_refreshPasswordStrength);

    _usernameController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();

    super.dispose();
  }

  // -----------------------------------
  // FORM VALIDATION
  // -----------------------------------

  String? _validateUsername(String? value) {
    final username = value?.trim() ?? '';

    if (username.isEmpty) {
      return 'Please enter a username';
    }

    final usernamePattern = RegExp(
      r'^[\p{L}\p{N}_.-]{3,50}$',
      unicode: true,
    );

    if (!usernamePattern.hasMatch(username)) {
      return 'Use 3-50 letters, numbers, _, . or -';
    }

    return null;
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';

    if (email.isEmpty) {
      return 'Please enter your email';
    }

    if (email.length > 255) {
      return 'Email address is too long';
    }

    final emailPattern = RegExp(
      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
    );

    if (!emailPattern.hasMatch(email)) {
      return 'Enter a valid email address';
    }

    return null;
  }

  String? _validateMobile(String? value) {
    final mobile = value?.trim() ?? '';

    if (mobile.isEmpty) {
      return 'Please enter your mobile number';
    }

    if (!RegExp(r'^\+?[0-9]{7,14}$').hasMatch(mobile)) {
      return 'Use 7-14 digits, optionally starting with +';
    }

    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';

    if (password.isEmpty) {
      return 'Please enter a password';
    }

    final byteLength = utf8.encode(password).length;

    if (byteLength < 8) {
      return 'Use at least 8 password bytes';
    }

    if (byteLength > 72) {
      return 'Password is too long (72-byte limit)';
    }

    return null;
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

  // -----------------------------------
  // PASSWORD STRENGTH
  // -----------------------------------

  int get _passwordStrength {
    final password = _passwordController.text;

    if (password.isEmpty) return 0;

    int score = 0;

    if (utf8.encode(password).length >= 8) {
      score++;
    }

    if (password.length >= 12) {
      score++;
    }

    if (RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[a-z]').hasMatch(password)) {
      score++;
    }

    if (RegExp(r'[0-9]').hasMatch(password) ||
        RegExp(r'[^a-zA-Z0-9]').hasMatch(password)) {
      score++;
    }

    return score;
  }

  Color get _strengthColor {
    switch (_passwordStrength) {
      case 1:
        return Colors.redAccent;
      case 2:
        return Colors.orangeAccent;
      case 3:
        return Colors.amber;
      case 4:
        return green;
      default:
        return border;
    }
  }

  String get _strengthLabel {
    switch (_passwordStrength) {
      case 1:
        return 'Weak';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Strong';
      default:
        return 'Enter a password';
    }
  }

  Widget _buildPasswordStrength() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(4, (index) {
            return Expanded(
              child: Container(
                height: 5,
                margin: EdgeInsets.only(
                  right: index == 3 ? 0 : 6,
                ),
                decoration: BoxDecoration(
                  color: index < _passwordStrength
                      ? _strengthColor
                      : border,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            );
          }),
        ),

        const SizedBox(height: 8),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Password strength',
              style: TextStyle(
                color: muted,
                fontSize: 12,
              ),
            ),

            Text(
              _strengthLabel,
              style: TextStyle(
                color: _strengthColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // -----------------------------------
  // NOTIFICATIONS
  // -----------------------------------

  void _showMessage(
      String message, {
        bool isError = true,
      }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? const Color(0xFFB83342)
            : const Color(0xFF166D55),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // -----------------------------------
  // REGISTER WITH PHP + MYSQL
  // -----------------------------------

  Future<void> _register() async {
    if (_isLoading) return;

    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final mobile = _mobileController.text.trim();

    // Do not trim passwords.
    final password = _passwordController.text;

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http
          .post(
        Uri.parse(registerUrl),
        body: {
          'username': username,
          'email': email,
          'mobile': mobile,
          'password': password,
        },
      )
          .timeout(const Duration(seconds: 20));

      if (!mounted) return;

      final dynamic decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        _showMessage('Unexpected server response.');
        return;
      }

      final success = decoded['success'] == true ||
          decoded['success'] == 1 ||
          decoded['success'] == 'true';

      final serverMessage = decoded['message'];

      final message = serverMessage is String
          ? serverMessage
          : 'Registration failed. Please try again.';

      if (response.statusCode == 200 && success) {
        // Registration does not log in the user.
        // Redirect to the Login screen.
        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const LoginScreen(),
          ),
        );
      } else {
        _showMessage(message);
      }
    } on TimeoutException {
      _showMessage(
        'Request timed out. Please check the server.',
      );
    } on FormatException {
      _showMessage(
        'The server returned invalid JSON. '
            'Check register.php.',
      );
    } catch (_) {
      _showMessage(
        'Cannot reach the registration server. '
            'Check your Wi-Fi and PHP server address.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // -----------------------------------
  // INPUT DESIGN
  // -----------------------------------

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,

      labelStyle: const TextStyle(
        color: muted,
      ),

      hintStyle: TextStyle(
        color: muted.withOpacity(0.6),
        fontSize: 13,
      ),

      prefixIcon: Icon(
        icon,
        color: cyan,
        size: 21,
      ),

      suffixIcon: suffixIcon,

      filled: true,
      fillColor: background,

      contentPadding: const EdgeInsets.symmetric(
        vertical: 18,
        horizontal: 16,
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
          width: 1.5,
        ),
      ),

      errorStyle: const TextStyle(
        color: Color(0xFFFF8A96),
      ),
    );
  }

  // -----------------------------------
  // HEADER
  // -----------------------------------

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF246D90),
                Color(0xFF10314B),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: cyan.withOpacity(0.5),
            ),
          ),
          child: const Icon(
            Icons.person_add_alt_1_rounded,
            color: cyan,
            size: 37,
          ),
        ),

        const SizedBox(height: 20),

        const Text(
          'CAMERA CONTROL',
          style: TextStyle(
            color: cyan,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),

        const SizedBox(height: 8),

        const Text(
          'Create your secure monitoring account',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: muted,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  // -----------------------------------
  // REGISTRATION FORM
  // -----------------------------------

  Widget _buildRegistrationForm() {
    return Container(
      padding: const EdgeInsets.all(23),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Create Account',
              style: TextStyle(
                color: Colors.white,
                fontSize: 27,
                fontWeight: FontWeight.w900,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Get started with your camera '
                  'management platform.',
              style: TextStyle(
                color: muted,
                fontSize: 13,
                height: 1.6,
              ),
            ),

            const SizedBox(height: 25),

            // USERNAME
            TextFormField(
              controller: _usernameController,
              enabled: !_isLoading,
              textInputAction: TextInputAction.next,
              style: const TextStyle(
                color: Colors.white,
              ),
              decoration: _inputDecoration(
                label: 'Username',
                hint: 'Choose a username',
                icon: Icons.person_outline_rounded,
              ),
              validator: _validateUsername,
            ),

            const SizedBox(height: 17),

            // EMAIL
            TextFormField(
              controller: _emailController,
              enabled: !_isLoading,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [
                AutofillHints.email,
              ],
              style: const TextStyle(
                color: Colors.white,
              ),
              decoration: _inputDecoration(
                label: 'Email Address',
                hint: 'example@gmail.com',
                icon: Icons.alternate_email_rounded,
              ),
              validator: _validateEmail,
            ),

            const SizedBox(height: 17),

            // MOBILE NUMBER
            TextFormField(
              controller: _mobileController,
              enabled: !_isLoading,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              autofillHints: const [
                AutofillHints.telephoneNumber,
              ],
              style: const TextStyle(
                color: Colors.white,
              ),
              decoration: _inputDecoration(
                label: 'Mobile Number',
                hint: '+967xxxxxxxxx',
                icon: Icons.phone_android_rounded,
              ),
              validator: _validateMobile,
            ),

            const SizedBox(height: 17),

            // PASSWORD
            TextFormField(
              controller: _passwordController,
              enabled: !_isLoading,
              obscureText: _hidePassword,
              textInputAction: TextInputAction.next,
              autofillHints: const [
                AutofillHints.newPassword,
              ],
              style: const TextStyle(
                color: Colors.white,
              ),
              decoration: _inputDecoration(
                label: 'Password',
                hint: 'Create a strong password',
                icon: Icons.lock_outline_rounded,
                suffixIcon: IconButton(
                  tooltip: _hidePassword
                      ? 'Show password'
                      : 'Hide password',
                  onPressed: () {
                    setState(() {
                      _hidePassword = !_hidePassword;
                    });
                  },
                  icon: Icon(
                    _hidePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: muted,
                  ),
                ),
              ),
              validator: _validatePassword,
            ),

            const SizedBox(height: 11),

            _buildPasswordStrength(),

            const SizedBox(height: 19),

            // CONFIRM PASSWORD
            TextFormField(
              controller: _confirmPasswordController,
              enabled: !_isLoading,
              obscureText: _hideConfirmPassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _register(),
              style: const TextStyle(
                color: Colors.white,
              ),
              decoration: _inputDecoration(
                label: 'Confirm Password',
                hint: 'Re-enter your password',
                icon: Icons.verified_user_outlined,
                suffixIcon: IconButton(
                  tooltip: _hideConfirmPassword
                      ? 'Show confirmation'
                      : 'Hide confirmation',
                  onPressed: () {
                    setState(() {
                      _hideConfirmPassword =
                      !_hideConfirmPassword;
                    });
                  },
                  icon: Icon(
                    _hideConfirmPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: muted,
                  ),
                ),
              ),
              validator: _validateConfirmPassword,
            ),

            const SizedBox(height: 25),

            // CREATE ACCOUNT BUTTON
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : _register,
                style: ElevatedButton.styleFrom(
                  backgroundColor: cyan,
                  foregroundColor: background,
                  disabledBackgroundColor:
                  cyan.withOpacity(0.4),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: background,
                  ),
                )
                    : const Row(
                  mainAxisAlignment:
                  MainAxisAlignment.center,
                  children: [
                    Text(
                      'Create Account',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    SizedBox(width: 10),

                    Icon(
                      Icons.arrow_forward_rounded,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 22),

            // SIGN IN LINK
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Flexible(
                  child: Text(
                    'Already have an account?',
                    style: TextStyle(
                      color: muted,
                      fontSize: 12,
                    ),
                  ),
                ),

                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                        const LoginScreen(),
                      ),
                    );
                  },
                  child: const Text(
                    'Sign In',
                    style: TextStyle(
                      color: cyan,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------
  // MAIN SCREEN
  // -----------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      resizeToAvoidBottomInset: true,

      appBar: AppBar(
        title: const Text(
          'Create Account',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
        backgroundColor: background,
        foregroundColor: Colors.white,
        elevation: 0,
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior:
          ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            20,
            20,
            20,
            35,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 480,
              ),
              child: Column(
                children: [
                  _buildHeader(),

                  const SizedBox(height: 30),

                  _buildRegistrationForm(),

                  const SizedBox(height: 25),

                  const Text(
                    'CAMERA CONTROL CENTER',
                    style: TextStyle(
                      color: muted,
                      fontSize: 10,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Secure monitoring • Smart surveillance',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: muted,
                      fontSize: 11,
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
