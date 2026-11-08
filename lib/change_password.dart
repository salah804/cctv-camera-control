
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState
    extends State<ChangePasswordScreen> {

  // ========================================
  // CCTV CAMERA CONTROL - CHANGE PASSWORD
  // ========================================

  static const Color _background =
  Color(0xFF080D18);

  static const Color _surface =
  Color(0xFF111C2D);

  static const Color _border =
  Color(0xFF26364B);

  static const Color _cyan =
  Color(0xFF50D5F5);

  static const Color _muted =
  Color(0xFF94A8C2);

  static const Color _green =
  Color(0xFF45E0AD);

  static const Color _red =
  Color(0xFFFF818D);

  // ========================================
  // PHP BACKEND
  // ========================================


  static const String _changePasswordUrl =
      'https://salahayash.helioho.st/cctv-api/change_password.php';


  // ========================================
  // FORM
  // ========================================

  final GlobalKey<FormState> _formKey =
  GlobalKey<FormState>();

  final TextEditingController
  _currentPasswordController =
  TextEditingController();

  final TextEditingController
  _newPasswordController =
  TextEditingController();

  final TextEditingController
  _confirmPasswordController =
  TextEditingController();

  final FlutterSecureStorage _secureStorage =
  const FlutterSecureStorage();

  bool _currentPasswordVisible = false;
  bool _newPasswordVisible = false;
  bool _confirmPasswordVisible = false;

  bool _isLoading = false;
  bool _isLoadingAccount = true;
  bool _isGoogleAccount = false;

  String _username = '';
  String _sessionToken = '';

  // ========================================
  // INITIALIZATION
  // ========================================

  @override
  void initState() {
    super.initState();
    _loadAccount();
  }

  Future<void> _loadAccount() async {
    try {
      final prefs =
      await SharedPreferences.getInstance();

      final token = await _secureStorage.read(
        key: 'session_token',
      );

      // This value is only used to decide
      // which interface to show.
      final authMethod =
      prefs.getString('auth_method');

      if (!mounted) return;

      setState(() {
        _username =
            prefs.getString('username') ?? '';

        _sessionToken = token ?? '';

        // Both account types now have tokens.
        // Never use token presence alone to
        // identify a Google account.
        //
        // Legacy Google sessions did not
        // have an auth_method value.

        _isGoogleAccount =
            authMethod == 'google' ||
                (authMethod == null &&
                    _sessionToken.isNotEmpty);

        _isLoadingAccount = false;
      });

    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoadingAccount = false;
      });

      _showMessage(
        'Could not load account information.',
        isError: true,
      );
    }
  }

  // ========================================
  // CLEANUP
  // ========================================

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ========================================
  // MESSAGES
  // ========================================

  void _showMessage(
      String message, {
        bool isError = false,
      }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isError
                    ? Icons.error_outline
                    : Icons.check_circle_outline,
                color: isError
                    ? _red
                    : _green,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(message),
              ),
            ],
          ),
          backgroundColor: _surface,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ========================================
  // CHANGE PASSWORD
  // ========================================

  Future<void> _changePassword() async {
    if (_isLoading ||
        _isLoadingAccount ||
        _isGoogleAccount) {
      return;
    }

    if (_formKey.currentState?.validate() != true) {
      return;
    }

    if (_username.isEmpty ||
        _sessionToken.isEmpty) {
      _showMessage(
        'Session missing. Please sign in again.',
        isError: true,
      );
      return;
    }

    final endpoint =
    Uri.tryParse(_changePasswordUrl);

    if (endpoint == null ||
        endpoint.scheme != 'https' ||
        endpoint.host.isEmpty) {
      _showMessage(
        'Change Password HTTPS backend '
            'is not configured.',
        isError: true,
      );
      return;
    }

    final currentPassword =
        _currentPasswordController.text;

    final newPassword =
        _newPasswordController.text;

    if (currentPassword == newPassword) {
      _showMessage(
        'Your new password must be different '
            'from your current password.',
        isError: true,
      );
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        endpoint,
        headers: {
          'Accept': 'application/json',

          // This will be checked by the
          // hardened PHP endpoint next.
          'Authorization':
          'Bearer $_sessionToken',
        },
        body: {
          // Backward compatibility with
          // the current PHP endpoint.
          // PHP must eventually derive
          // identity from the token instead.
          'username': _username,
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        },
      ).timeout(
        const Duration(seconds: 20),
      );

      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes),
      );

      if (decoded is! Map) {
        throw const FormatException(
          'Unexpected PHP response.',
        );
      }

      if (!mounted) return;

      if (response.statusCode == 200 &&
          decoded['success'] == true) {

        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();

        _showMessage(
          'Password changed successfully!',
        );

        Navigator.of(context).pop(true);

      } else {
        _showMessage(
          decoded['message']?.toString() ??
              'Could not change password.',
          isError: true,
        );
      }

    } on TimeoutException {
      _showMessage(
        'Connection timed out. Please try again.',
        isError: true,
      );

    } on FormatException {
      _showMessage(
        'Invalid PHP server response.',
        isError: true,
      );

    } catch (_) {
      _showMessage(
        'Connection failed. Please check '
            'your internet and PHP server.',
        isError: true,
      );

    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ========================================
  // PASSWORD FIELD
  // ========================================

  Widget _passwordField({
    required String label,
    required TextEditingController controller,
    required bool visible,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
    TextInputAction textInputAction =
        TextInputAction.next,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: !visible,
      enabled: !_isLoading,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: textInputAction,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
      ),
      validator: validator,
      onFieldSubmitted: (_) {
        if (textInputAction ==
            TextInputAction.done) {
          _changePassword();
        }
      },
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: _muted,
        ),
        prefixIcon: const Icon(
          Icons.lock_outline,
          color: _cyan,
        ),
        suffixIcon: IconButton(
          tooltip: visible
              ? 'Hide password'
              : 'Show password',
          onPressed: _isLoading
              ? null
              : onToggle,
          icon: Icon(
            visible
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: _muted,
          ),
        ),
        filled: true,
        fillColor: _background,
        contentPadding:
        const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: _border,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: _cyan,
            width: 1.6,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: _red,
          ),
        ),
        focusedErrorBorder:
        OutlineInputBorder(
          borderRadius:
          BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: _red,
            width: 1.6,
          ),
        ),
      ),
    );
  }

  // ========================================
  // GOOGLE ACCOUNT NOTICE
  // ========================================

  Widget _buildGoogleNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius:
        BorderRadius.circular(20),
        border: Border.all(
          color: _border,
        ),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.info_outline,
            size: 48,
            color: _cyan,
          ),

          SizedBox(height: 16),

          Text(
            'Google Account',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),

          SizedBox(height: 12),

          Text(
            'You signed in with Google.\n\n'
                'Your Google password is managed '
                'by Google, not by this CCTV app.\n\n'
                'To change it, visit the Security '
                'section of your Google Account.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _muted,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  // ========================================
  // PASSWORD CHANGE FORM
  // ========================================

  Widget _buildPasswordForm() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius:
        BorderRadius.circular(22),
        border: Border.all(
          color: _border,
        ),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            const Text(
              'UPDATE PASSWORD',
              style: TextStyle(
                color: _cyan,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.4,
              ),
            ),

            const SizedBox(height: 12),

            const Text(
              'Protect your account',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Enter your current password '
                  'and choose a new one.',
              style: TextStyle(
                color: _muted,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 28),

            // CURRENT PASSWORD

            _passwordField(
              label: 'Current Password',
              controller:
              _currentPasswordController,
              visible:
              _currentPasswordVisible,
              onToggle: () {
                setState(() {
                  _currentPasswordVisible =
                  !_currentPasswordVisible;
                });
              },
              validator: (value) {
                if (value == null ||
                    value.isEmpty) {
                  return 'Enter your current password';
                }
                return null;
              },
            ),

            const SizedBox(height: 18),

            // NEW PASSWORD

            _passwordField(
              label: 'New Password',
              controller:
              _newPasswordController,
              visible:
              _newPasswordVisible,
              onToggle: () {
                setState(() {
                  _newPasswordVisible =
                  !_newPasswordVisible;
                });
              },
              validator: (value) {
                if (value == null ||
                    value.isEmpty) {
                  return 'Enter a new password';
                }

                if (value.length < 8) {
                  return 'Use at least 8 characters';
                }

                if (utf8.encode(value).length > 72) {
                  return 'Password is too long';
                }

                return null;
              },
            ),

            const SizedBox(height: 18),

            // CONFIRM NEW PASSWORD

            _passwordField(
              label: 'Confirm New Password',
              controller:
              _confirmPasswordController,
              visible:
              _confirmPasswordVisible,
              onToggle: () {
                setState(() {
                  _confirmPasswordVisible =
                  !_confirmPasswordVisible;
                });
              },
              validator: (value) {
                if (value == null ||
                    value.isEmpty) {
                  return 'Confirm your new password';
                }

                if (value !=
                    _newPasswordController.text) {
                  return 'Passwords do not match';
                }

                return null;
              },
              textInputAction:
              TextInputAction.done,
            ),

            const SizedBox(height: 16),

            const Row(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.shield_outlined,
                  color: _muted,
                  size: 18,
                ),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Choose a unique password '
                        'with at least 8 characters.',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 26),

            // SUBMIT BUTTON

            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                onPressed: _isLoading
                    ? null
                    : _changePassword,
                icon: _isLoading
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child:
                  CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _background,
                  ),
                )
                    : const Icon(
                  Icons.lock_reset_outlined,
                ),
                label: Text(
                  _isLoading
                      ? 'Updating Password...'
                      : 'Change Password',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _cyan,
                  foregroundColor: _background,
                  disabledBackgroundColor:
                  _cyan.withValues(
                    alpha: 0.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========================================
  // MAIN SCREEN
  // ========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,

      appBar: AppBar(
        title: const Text(
          'Change Password',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: _background,
        foregroundColor: Colors.white,
        elevation: 0,
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 500,
              ),
              child: Column(
                children: [
                  const SizedBox(height: 20),

                  Container(
                    width: 85,
                    height: 85,
                    decoration: BoxDecoration(
                      color: _cyan.withValues(
                        alpha: 0.1,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _cyan.withValues(
                          alpha: 0.3,
                        ),
                      ),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_outlined,
                      color: _cyan,
                      size: 43,
                    ),
                  ),

                  const SizedBox(height: 18),

                  const Text(
                    'Account Security',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 9),

                  const Text(
                    'Manage your password securely',
                    style: TextStyle(
                      color: _muted,
                    ),
                  ),

                  const SizedBox(height: 30),

                  if (_isLoadingAccount)
                    const Center(
                      child:
                      CircularProgressIndicator(
                        color: _cyan,
                      ),
                    )
                  else if (_isGoogleAccount)
                    _buildGoogleNotice()
                  else
                    _buildPasswordForm(),

                  const SizedBox(height: 28),

                  const Text(
                    'CAMERA CONTROL • ACCOUNT SECURITY',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _muted,
                      fontSize: 10,
                      letterSpacing: 1.1,
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
