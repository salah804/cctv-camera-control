
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() =>
      _ForgotPasswordPageState();
}

class _ForgotPasswordPageState
    extends State<ForgotPasswordPage> {

  // ========================================
  // CCTV CAMERA CONTROL - FORGOT PASSWORD
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
  Color(0xFF94A3B8);

  // ========================================
  // BACKEND CONFIGURATION
  // ========================================
  // This endpoint will be created in PHP.
  // Supply its HTTPS URL using:
  //
  // --dart-define=CCTV_PASSWORD_RESET_REQUEST_URL=...
  //
  // Do not use the old check_email.php
  // or unverified reset_password.php.
  // ========================================

  
static const String _requestResetUrl =
    'https://salahayash.helioho.st/cctv-api/request_password_reset.php';


  // ========================================
  // CONTROLLERS
  // ========================================

  final TextEditingController _emailController =
  TextEditingController();

  bool _isLoading = false;
  bool _requestSent = false;

  String _submittedEmail = '';

  // ========================================
  // DISPOSE
  // ========================================

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  // ========================================
  // SHOW MESSAGE
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
          content: Text(message),
          backgroundColor:
          isError
              ? const Color(0xFFB91C1C)
              : const Color(0xFF167D69),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  // ========================================
  // VALIDATE EMAIL
  // ========================================

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(
      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
    );

    return emailRegex.hasMatch(email);
  }

  // ========================================
  // REQUEST PASSWORD RESET
  // ========================================

  Future<void> _requestPasswordReset() async {

    if (_isLoading) return;

    final String email =
    _emailController.text.trim();

    // ======================================
    // EMAIL VALIDATION
    // ======================================

    if (email.isEmpty) {
      _showMessage(
        'Please enter your email address.',
        isError: true,
      );
      return;
    }

    if (!_isValidEmail(email)) {
      _showMessage(
        'Please enter a valid email address.',
        isError: true,
      );
      return;
    }

    // ======================================
    // CHECK BACKEND CONFIGURATION
    // ======================================

    if (_requestResetUrl.isEmpty) {
      _showMessage(
        'Password recovery backend is not configured yet.',
        isError: true,
      );
      return;
    }

    final Uri? uri =
    Uri.tryParse(_requestResetUrl);

    if (uri == null || uri.scheme != 'https') {
      _showMessage(
        'A valid HTTPS recovery endpoint is required.',
        isError: true,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // ======================================
    // SEND REQUEST
    // ======================================

    try {

      final response = await http.post(
        uri,
        headers: {
          'Accept': 'application/json',
        },
        body: {
          'email': email,
        },
      ).timeout(
        const Duration(seconds: 20),
      );

      if (!mounted) return;

      // ====================================
      // PARSE SERVER RESPONSE
      // ====================================

      Map<String, dynamic> responseData = {};

      try {
        final decoded =
        jsonDecode(response.body);

        if (decoded is Map<String, dynamic>) {
          responseData = decoded;
        }
      } catch (_) {
        // Do not expose raw server responses.
      }

      // ====================================
      // SUCCESS
      // ====================================

      if (
      (response.statusCode == 200 ||
          response.statusCode == 202) &&
          responseData['success'] == true
      ) {

        setState(() {
          _requestSent = true;
          _submittedEmail = email;
        });

        return;
      }

      // ====================================
      // RATE LIMIT
      // ====================================

      if (response.statusCode == 429) {
        _showMessage(
          'Too many requests. Please try again later.',
          isError: true,
        );
        return;
      }

      // ====================================
      // OTHER ERRORS
      // ====================================

      _showMessage(
        'Unable to process your request. Please try again later.',
        isError: true,
      );

    } on TimeoutException {

      _showMessage(
        'Connection timed out. Please try again.',
        isError: true,
      );

    } catch (_) {

      if (!mounted) return;

      _showMessage(
        'Network error. Please check your connection.',
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
  // RESET SCREEN
  // ========================================

  void _tryAnotherEmail() {

    setState(() {
      _requestSent = false;
      _submittedEmail = '';
      _emailController.clear();
    });
  }

  // ========================================
  // EMAIL FIELD DECORATION
  // ========================================

  InputDecoration _emailDecoration() {

    return InputDecoration(
      hintText: 'you@example.com',
      hintStyle: const TextStyle(
        color: _muted,
      ),
      prefixIcon: const Icon(
        Icons.alternate_email_rounded,
        color: _cyan,
      ),
      filled: true,
      fillColor: _background,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 18,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: _border,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: _cyan,
          width: 1.5,
        ),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }

  // ========================================
  // INITIAL EMAIL FORM
  // ========================================

  Widget _buildEmailForm() {

    return Column(
      key: const ValueKey('emailForm'),
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [

        const Text(
          'EMAIL ADDRESS',
          style: TextStyle(
            color: _muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),

        const SizedBox(height: 12),

        TextField(
          controller: _emailController,
          keyboardType:
          TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autofillHints: const [
            AutofillHints.email,
          ],
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
          ),
          decoration: _emailDecoration(),
          onSubmitted: (_) =>
              _requestPasswordReset(),
        ),

        const SizedBox(height: 18),

        const Text(
          'We will send password recovery instructions '
              'if an account is associated with this email.',
          style: TextStyle(
            color: _muted,
            fontSize: 13,
            height: 1.6,
          ),
        ),

        const SizedBox(height: 28),

        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton.icon(
            onPressed: _isLoading
                ? null
                : _requestPasswordReset,
            style: ElevatedButton.styleFrom(
              backgroundColor: _cyan,
              foregroundColor: _background,
              disabledBackgroundColor:
              _cyan.withValues(alpha: 0.5),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(14),
              ),
            ),
            icon: _isLoading
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _background,
              ),
            )
                : const Icon(
              Icons.mark_email_read_outlined,
              size: 21,
            ),
            label: Text(
              _isLoading
                  ? 'Sending Request...'
                  : 'Send Reset Link',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),

      ],
    );
  }

  // ========================================
  // EMAIL REQUESTED SCREEN
  // ========================================

  Widget _buildSuccessView() {

    return Column(
      key: const ValueKey('successView'),
      children: [

        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: const Color(0xFF123D39),
            borderRadius:
            BorderRadius.circular(22),
          ),
          child: const Icon(
            Icons.mark_email_read_outlined,
            color: Color(0xFF52E0BF),
            size: 38,
          ),
        ),

        const SizedBox(height: 24),

        const Text(
          'Check Your Inbox',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 23,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 12),

        Text(
          _submittedEmail,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _cyan,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),

        const SizedBox(height: 18),

        const Text(
          'If an account exists for this email, '
              'you will receive a secure password-reset link. '
              'Open the link to verify your request and '
              'create a new password.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _muted,
            fontSize: 14,
            height: 1.7,
          ),
        ),

        const SizedBox(height: 20),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _background,
            borderRadius:
            BorderRadius.circular(12),
            border: Border.all(
              color: _border,
            ),
          ),
          child: const Row(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                color: _cyan,
                size: 19,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'If you do not receive an email, '
                      'check your spam folder or try again later.',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 26),

        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).maybePop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _cyan,
              foregroundColor: _background,
              shape: RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(
              Icons.arrow_back_rounded,
            ),
            label: const Text(
              'Back to Login',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),

        const SizedBox(height: 10),

        TextButton(
          onPressed: _tryAnotherEmail,
          child: const Text(
            'Use Another Email',
            style: TextStyle(
              color: _cyan,
            ),
          ),
        ),

      ],
    );
  }

  // ========================================
  // GOOGLE ACCOUNT INFORMATION
  // ========================================

  Widget _buildGoogleNotice() {

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius:
        BorderRadius.circular(16),
        border: Border.all(
          color: _border,
        ),
      ),
      child: const Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [

          Icon(
            Icons.g_mobiledata_rounded,
            color: _cyan,
            size: 28,
          ),

          SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [

                Text(
                  'Signed in with Google?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                SizedBox(height: 7),

                Text(
                  'If you use Google Sign-In, '
                      'your Google password is managed '
                      'by Google. Use Google Account '
                      'Recovery instead.',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),

              ],
            ),
          ),

        ],
      ),
    );
  }

  // ========================================
  // BUILD
  // ========================================

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: _background,

      appBar: AppBar(
        backgroundColor: _background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(
          color: Colors.white,
        ),
        title: const Text(
          'Forgot Password',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      body: Stack(
        children: [

          // BACKGROUND GLOW

          Positioned(
            top: -120,
            right: -100,
            child: IgnorePointer(
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _cyan.withValues(alpha: 0.13),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // MAIN CONTENT

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                20,
                30,
                20,
                35,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints:
                  const BoxConstraints(
                    maxWidth: 450,
                  ),
                  child: Column(
                    children: [

                      // HEADER ICON

                      Container(
                        height: 90,
                        width: 90,
                        decoration: BoxDecoration(
                          color: _surface,
                          borderRadius:
                          BorderRadius.circular(26),
                          border: Border.all(
                            color: _border,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _cyan.withValues(
                                alpha: 0.1,
                              ),
                              blurRadius: 30,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.lock_reset_rounded,
                          size: 46,
                          color: _cyan,
                        ),
                      ),

                      const SizedBox(height: 25),

                      Text(
                        _requestSent
                            ? 'Recovery Requested'
                            : 'Reset Your Password',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 27,
                          fontWeight:
                          FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 12),

                      Text(
                        _requestSent
                            ? 'Follow the recovery instructions sent to your email.'
                            : 'Enter your email address to request a secure password-reset link.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 14,
                          height: 1.6,
                        ),
                      ),

                      const SizedBox(height: 32),

                      // MAIN CARD

                      Container(
                        width: double.infinity,
                        padding:
                        const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: _surface,
                          borderRadius:
                          BorderRadius.circular(22),
                          border: Border.all(
                            color: _border,
                          ),
                        ),
                        child: AnimatedSwitcher(
                          duration:
                          const Duration(
                            milliseconds: 250,
                          ),
                          child: _requestSent
                              ? _buildSuccessView()
                              : _buildEmailForm(),
                        ),
                      ),

                      const SizedBox(height: 20),

                      _buildGoogleNotice(),

                      const SizedBox(height: 25),

                      if (!_requestSent)
                        TextButton.icon(
                          onPressed: () {
                            Navigator.of(context)
                                .maybePop();
                          },
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            size: 18,
                          ),
                          label: const Text(
                            'Back to Login',
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: _cyan,
                          ),
                        ),

                      const SizedBox(height: 10),

                      const Text(
                        'CCTV CAMERA CONTROL',
                        style: TextStyle(
                          color: _muted,
                          fontSize: 10,
                          letterSpacing: 2,
                          fontWeight:
                          FontWeight.w600,
                        ),
                      ),

                    ],
                  ),
                ),
              ),
            ),
          ),

        ],
      ),
    );
  }
}
