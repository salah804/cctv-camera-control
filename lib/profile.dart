
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Profile extends StatefulWidget {
  const Profile({super.key});

  @override
  State<Profile> createState() => _ProfileState();
}

class _ProfileState extends State<Profile> {
  // ========================================
  // THEME
  // ========================================

  static const Color bg = Color(0xFF080D18);
  static const Color surface = Color(0xFF111C2D);
  static const Color border = Color(0xFF26364B);
  static const Color cyan = Color(0xFF50D5F5);
  static const Color muted = Color(0xFF94A8C2);
  static const Color green = Color(0xFF4ADE80);

  // ========================================
  // HELIOHOST API
  // ========================================

  static const String detailsUrl =
      'https://salahayash.helioho.st/cctv-api/getUserDetails.php';

  static const String updateUrl =
      'https://salahayash.helioho.st/cctv-api/update_profile.php';

  // ========================================
  // CONTROLLERS
  // ========================================

  final _formKey = GlobalKey<FormState>();

  final _usernameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();
  final _locationController = TextEditingController();
  final _companyController = TextEditingController();
  final _jobTitleController = TextEditingController();
  final _bioController = TextEditingController();

  final ImagePicker _imagePicker = ImagePicker();

  String _accountUsername = '';

  Uint8List? imageBytes;
  Map<String, String> _originalValues = {};

  bool _isLoading = true;
  bool _isEditing = false;
  bool _isSaving = false;
  bool _isUploadingImage = false;

  String? _loadError;

  // ========================================
  // IN-MEMORY PROFILE CACHE
  // ========================================

  static String? _cachedAuthorization;
  static String? _cachedUsername;
  static String? _cachedDisplayUsername;
  static Map<String, String>? _cachedFields;
  static Uint8List? _cachedPhoto;

  void _rememberProfile() {
    _cachedUsername = _accountUsername;
    _cachedDisplayUsername = _usernameController.text;
    _cachedFields =
    Map<String, String>.from(_currentFields());
    _cachedPhoto = imageBytes;
  }

  static void _clearProfileCache() {
    _cachedAuthorization = null;
    _cachedUsername = null;
    _cachedDisplayUsername = null;
    _cachedFields = null;
    _cachedPhoto = null;
  }

  // ========================================
  // INITIALIZATION
  // ========================================

  @override
  void initState() {
    super.initState();
    _openProfileFast();
  }

  Future<void> _openProfileFast() async {
    try {
      final headers = await _profileHeaders();

      if (!mounted) return;

      final sameSession =
          _cachedAuthorization == headers['Authorization'];

      if (sameSession &&
          _cachedUsername != null &&
          _cachedFields != null) {
        setState(() {
          _accountUsername = _cachedUsername!;

          _usernameController.text =
              _cachedDisplayUsername ?? _cachedUsername!;

          _applyFields(_cachedFields!);

          _originalValues =
          Map<String, String>.from(_cachedFields!);

          imageBytes = _cachedPhoto;

          _isEditing = false;
          _isLoading = false;
          _loadError = null;
        });

        debugPrint(
          'Profile opened instantly from memory cache',
        );
        return;
      }
    } catch (_) {
      // Normal loading handles authentication errors.
    }

    await _loadProfile();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    _locationController.dispose();
    _companyController.dispose();
    _jobTitleController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  // ========================================
  // HELPERS
  // ========================================

  String _value(dynamic value) {
    return value?.toString() ?? '';
  }

  bool _isSuccess(dynamic response) {
    if (response is! Map) return false;

    final success = response['success'];

    return success == true ||
        success == 1 ||
        success == 'true';
  }

  String _responseMessage(
      dynamic response,
      String fallback,
      ) {
    if (response is Map &&
        response['message'] is String) {
      return response['message'] as String;
    }

    return fallback;
  }

  void _showMessage(
      String message, {
        bool error = false,
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
          duration: const Duration(seconds: 3),
        ),
      );
  }

  // ========================================
  // AUTHENTICATION
  // ========================================

  Future<Map<String, String>> _profileHeaders() async {
    final token = await const FlutterSecureStorage()
        .read(key: 'session_token');

    if (token == null || token.isEmpty) {
      throw Exception('Please sign in again.');
    }

    return {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ========================================
  // PROFILE FIELDS
  // ========================================

  Map<String, String> _currentFields() {
    return {
      'full_name': _fullNameController.text,
      'email': _emailController.text,
      'mobile': _mobileController.text,
      'location': _locationController.text,
      'company': _companyController.text,
      'job_title': _jobTitleController.text,
      'bio': _bioController.text,
    };
  }

  void _applyFields(Map<String, String> values) {
    _fullNameController.text =
        values['full_name'] ?? '';

    _emailController.text =
        values['email'] ?? '';

    _mobileController.text =
        values['mobile'] ?? '';

    _locationController.text =
        values['location'] ?? '';

    _companyController.text =
        values['company'] ?? '';

    _jobTitleController.text =
        values['job_title'] ?? '';

    _bioController.text =
        values['bio'] ?? '';
  }

  // ========================================
  // LOAD PROFILE FROM HELIOHOST
  // ========================================

  Future<void> _loadProfile() async {
    if (!mounted) return;

    final timer = Stopwatch()..start();

    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final prefs =
      await SharedPreferences.getInstance();

      final username =
          prefs.getString('username')?.trim() ?? '';

      if (username.isEmpty) {
        throw Exception(
          'No account found. Please sign in again.',
        );
      }

      final headers = await _profileHeaders();

      final uri = Uri.parse(detailsUrl).replace(
        queryParameters: {
          'username': username,
        },
      );

      final response = await http
          .get(
        uri,
        headers: headers,
      )
          .timeout(const Duration(seconds: 15));

      debugPrint(
        'Profile GET HTTP ${response.statusCode} '
            'after ${timer.elapsedMilliseconds} ms',
      );

      final decoded = jsonDecode(response.body);

      if (response.statusCode == 401 ||
          response.statusCode == 403) {
        _clearProfileCache();
      }

      if (response.statusCode != 200 ||
          !_isSuccess(decoded)) {
        throw Exception(
          _responseMessage(
            decoded,
            'Unable to load profile.',
          ),
        );
      }

      final dynamic data = decoded['data'];

      if (data is! Map<String, dynamic>) {
        throw Exception(
          'Invalid profile information returned.',
        );
      }

      Uint8List? photo;

      final encodedImage = data['image'];

      if (encodedImage is String &&
          encodedImage.isNotEmpty) {
        try {
          photo = base64Decode(encodedImage);
        } catch (_) {
          photo = null;
        }
      }

      final fields = <String, String>{
        'full_name': _value(data['full_name']),
        'email': _value(data['email']),
        'mobile': _value(data['mobile']),
        'location': _value(data['location']),
        'company': _value(data['company']),
        'job_title': _value(data['job_title']),
        'bio': _value(data['bio']),
      };

      if (!mounted) return;

      setState(() {
        _accountUsername = username;

        final serverUsername =
        _value(data['username']);

        _usernameController.text =
        serverUsername.isNotEmpty
            ? serverUsername
            : username;

        _applyFields(fields);

        _originalValues =
        Map<String, String>.from(fields);

        imageBytes = photo;

        _isEditing = false;
        _loadError = null;
      });

      // Store only successfully loaded profile data.
      _cachedAuthorization = headers['Authorization'];
      _rememberProfile();

    } on TimeoutException {
      if (mounted) {
        setState(() {
          _loadError =
          'Connection timed out. Check your internet.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e.toString().replaceFirst(
            'Exception: ',
            '',
          );
        });
      }
    } finally {
      timer.stop();

      debugPrint(
        'Profile load total '
            '${timer.elapsedMilliseconds} ms',
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ========================================
  // EDITING
  // ========================================

  void _startEditing() {
    if (_isEditing || _isSaving) return;

    setState(() {
      _isEditing = true;
    });
  }

  void _cancelEditing() {
    FocusScope.of(context).unfocus();

    setState(() {
      _applyFields(_originalValues);
      _isEditing = false;
    });

    _formKey.currentState?.reset();
    _applyFields(_originalValues);
  }

  // ========================================
  // VALIDATION
  // ========================================

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';

    if (email.isEmpty) {
      return 'Email is required';
    }

    if (email.length > 255 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
            .hasMatch(email)) {
      return 'Enter a valid email address';
    }

    return null;
  }

  String? _validateMobile(String? value) {
    final mobile = value?.trim() ?? '';

    if (mobile.isEmpty) return null;

    if (!RegExp(r'^\+?[0-9]{7,14}$')
        .hasMatch(mobile)) {
      return 'Use 7-14 digits, optionally starting with +';
    }

    return null;
  }

  // ========================================
  // SAVE PROFILE
  // ========================================

  Future<void> _saveProfile() async {
    if (_isSaving || !_isEditing) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isSaving = true;
    });

    try {
      final body = {
        'action': 'update_details',
        'username': _accountUsername,
        'full_name':
        _fullNameController.text.trim(),
        'email':
        _emailController.text.trim(),
        'mobile':
        _mobileController.text.trim(),
        'location':
        _locationController.text.trim(),
        'company':
        _companyController.text.trim(),
        'job_title':
        _jobTitleController.text.trim(),
        'bio':
        _bioController.text.trim(),
      };

      final response = await http
          .post(
        Uri.parse(updateUrl),
        headers: await _profileHeaders(),
        body: body,
      )
          .timeout(const Duration(seconds: 20));

      final decoded = jsonDecode(response.body);

      if (response.statusCode == 200 &&
          _isSuccess(decoded)) {
        if (!mounted) return;

        final savedFields = <String, String>{
          'full_name': body['full_name']!,
          'email': body['email']!,
          'mobile': body['mobile']!,
          'location': body['location']!,
          'company': body['company']!,
          'job_title': body['job_title']!,
          'bio': body['bio']!,
        };

        setState(() {
          _originalValues =
          Map<String, String>.from(savedFields);

          _applyFields(savedFields);
          _isEditing = false;
        });

        // Update memory cache after successful save.
        _rememberProfile();

        _showMessage(
          'Profile updated successfully!',
        );
      } else {
        _showMessage(
          _responseMessage(
            decoded,
            'Profile update failed.',
          ),
          error: true,
        );
      }
    } on TimeoutException {
      _showMessage(
        'Profile update timed out.',
        error: true,
      );
    } on FormatException {
      _showMessage(
        'Invalid server response.',
        error: true,
      );
    } catch (_) {
      _showMessage(
        'Unable to save changes. Check your connection.',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // ========================================
  // PICK IMAGE
  // ========================================

  Future<void> _pickImage() async {
    if (_isUploadingImage) return;

    try {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 320,
        maxHeight: 320,
        imageQuality: 55,
      );

      if (pickedFile == null) return;

      final Uint8List bytes =
      await pickedFile.readAsBytes();

      debugPrint(
        'Selected profile photo size: '
            '${bytes.length} bytes',
      );

      if (bytes.length > 2 * 1024 * 1024) {
        _showMessage(
          'Image must be smaller than 2 MB.',
          error: true,
        );
        return;
      }

      await _uploadImage(
        bytes,
        pickedFile.name,
      );
    } catch (e) {
      debugPrint(
        'Profile picker error: ${e.runtimeType}',
      );

      _showMessage(
        'Unable to select the picture.',
        error: true,
      );
    }
  }

  // ========================================
  // UPLOAD IMAGE
  // ========================================

  Future<void> _uploadImage(
      Uint8List bytes,
      String filename,
      ) async {
    if (_isUploadingImage) return;

    final timer = Stopwatch()..start();

    setState(() {
      _isUploadingImage = true;
    });

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(updateUrl),
      );

      request.headers.addAll(
        await _profileHeaders(),
      );

      request.fields['action'] = 'upload_image';

      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: filename,
        ),
      );

      final streamedResponse = await request
          .send()
          .timeout(const Duration(seconds: 30));

      final response =
      await http.Response.fromStream(
        streamedResponse,
      ).timeout(const Duration(seconds: 30));

      debugPrint(
        'Profile upload HTTP ${response.statusCode} '
            'after ${timer.elapsedMilliseconds} ms',
      );

      Map<String, dynamic>? decoded;

      try {
        final parsed = jsonDecode(response.body);

        if (parsed is Map<String, dynamic>) {
          decoded = parsed;
        }
      } on FormatException {
        debugPrint(
          'Profile upload response was not JSON',
        );
      }

      if (response.statusCode == 200 &&
          decoded != null &&
          _isSuccess(decoded)) {
        if (!mounted) return;

        setState(() {
          imageBytes = bytes;
        });

        // Remember the newly uploaded image.
        _rememberProfile();

        _showMessage(
          'Profile picture updated!',
        );
      } else {
        final serverMessage = decoded == null
            ? 'Server rejected photo '
            '(HTTP ${response.statusCode}).'
            : _responseMessage(
          decoded,
          'Image upload failed '
              '(HTTP ${response.statusCode}).',
        );

        debugPrint(
          'Profile upload unsuccessful: $serverMessage',
        );

        _showMessage(
          serverMessage,
          error: true,
        );
      }
    } on TimeoutException {
      _showMessage(
        'Photo upload timed out. Check your connection.',
        error: true,
      );
    } catch (e) {
      debugPrint(
        'Profile upload exception: ${e.runtimeType}',
      );

      _showMessage(
        'Unable to upload photo (${e.runtimeType}).',
        error: true,
      );
    } finally {
      timer.stop();

      if (mounted) {
        setState(() {
          _isUploadingImage = false;
        });
      }
    }
  }

  // ========================================
  // REMOVE IMAGE
  // ========================================

  Future<void> _removeImage() async {
    if (_isUploadingImage || imageBytes == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: surface,
          title: const Text(
            'Remove Profile Picture?',
            style: TextStyle(
              color: Colors.white,
            ),
          ),
          content: const Text(
            'Your account will display a default avatar.',
            style: TextStyle(
              color: muted,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text(
                'Remove',
                style: TextStyle(
                  color: Colors.redAccent,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isUploadingImage = true;
    });

    try {
      final response = await http
          .post(
        Uri.parse(updateUrl),
        headers: await _profileHeaders(),
        body: {
          'username': _accountUsername,
          'action': 'remove_image',
        },
      )
          .timeout(const Duration(seconds: 15));

      final decoded = jsonDecode(response.body);

      if (response.statusCode == 200 &&
          _isSuccess(decoded)) {
        if (!mounted) return;

        setState(() {
          imageBytes = null;
        });

        // Remove the image from memory cache too.
        _rememberProfile();

        _showMessage(
          'Profile picture removed.',
        );
      } else {
        _showMessage(
          _responseMessage(
            decoded,
            'Unable to remove the picture.',
          ),
          error: true,
        );
      }
    } catch (_) {
      _showMessage(
        'Failed to remove the picture.',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingImage = false;
        });
      }
    }
  }

  // ========================================
  // CARD DESIGN
  // ========================================

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: border),
    );
  }

  Widget _sectionTitle(
      String title,
      IconData icon,
      ) {
    return Row(
      children: [
        Icon(icon, color: cyan, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(19),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(title, icon),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  // ========================================
  // REUSABLE TEXT FIELD
  // ========================================

  Widget _field({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    bool alwaysReadOnly = false,
    int maxLines = 1,
    int? maxLength,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        readOnly: alwaysReadOnly,
        enabled: !_isSaving,
        maxLines: maxLines,
        maxLength: maxLength,
        keyboardType: keyboardType,
        cursorColor: cyan,
        textInputAction: maxLines > 1
            ? TextInputAction.newline
            : TextInputAction.next,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        onTap: () {
          if (!alwaysReadOnly && !_isEditing) {
            _startEditing();
          }
        },
        onChanged: (_) {
          if (!alwaysReadOnly && !_isEditing) {
            _startEditing();
          }
        },
        validator: alwaysReadOnly ? null : validator,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: muted),
          counterText: '',
          prefixIcon: Icon(
            icon,
            color: cyan,
            size: 21,
          ),
          suffixIcon: alwaysReadOnly
              ? const Icon(
            Icons.lock_outline,
            color: muted,
            size: 18,
          )
              : _isEditing
              ? const Icon(
            Icons.edit_outlined,
            color: cyan,
            size: 18,
          )
              : null,
          filled: true,
          fillColor: bg,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 15,
            vertical: 18,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(
              color: cyan,
              width: 1.5,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(
              color: Colors.redAccent,
            ),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(
              color: Colors.redAccent,
            ),
          ),
        ),
      ),
    );
  }

  // ========================================
  // PROFILE HEADER
  // ========================================

  Widget _buildProfileHeader() {
    final fullName =
    _fullNameController.text.trim();

    final displayName = fullName.isNotEmpty
        ? fullName
        : _usernameController.text;

    final subtitleParts = [
      _jobTitleController.text.trim(),
      _companyController.text.trim(),
    ].where((part) => part.isNotEmpty).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF15364B),
            Color(0xFF111C2D),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(23),
        border: Border.all(
          color: const Color(0xFF25617B),
        ),
      ),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: _isUploadingImage
                    ? null
                    : _pickImage,
                child: Container(
                  width: 115,
                  height: 115,
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: cyan,
                  ),
                  child: CircleAvatar(
                    backgroundColor: bg,
                    backgroundImage: imageBytes != null
                        ? MemoryImage(imageBytes!)
                        : null,
                    child: imageBytes == null
                        ? const Icon(
                      Icons.person_rounded,
                      color: cyan,
                      size: 62,
                    )
                        : null,
                  ),
                ),
              ),
              Positioned(
                right: -5,
                bottom: 1,
                child: Material(
                  color: cyan,
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Change profile picture',
                    onPressed: _isUploadingImage
                        ? null
                        : _pickImage,
                    icon: const Icon(
                      Icons.camera_alt_rounded,
                      color: bg,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (_isUploadingImage) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(color: cyan),
          ],

          const SizedBox(height: 20),

          Text(
            displayName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),

          const SizedBox(height: 7),

          Text(
            '@${_usernameController.text}',
            style: const TextStyle(
              color: cyan,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),

          if (subtitleParts.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              subtitleParts.join(' • '),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: muted,
                fontSize: 12,
              ),
            ),
          ],

          const SizedBox(height: 18),

          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.account_circle_outlined,
                color: green,
                size: 18,
              ),
              SizedBox(width: 7),
              Text(
                'ACCOUNT PROFILE',
                style: TextStyle(
                  color: green,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),

          if (imageBytes != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _isUploadingImage
                  ? null
                  : _removeImage,
              icon: const Icon(
                Icons.delete_outline,
                size: 18,
              ),
              label: const Text('Remove Photo'),
              style: TextButton.styleFrom(
                foregroundColor:
                const Color(0xFFFF9AA5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ========================================
  // EDIT / SAVE / CANCEL BUTTONS
  // ========================================

  Widget _buildActions() {
    if (!_isEditing) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _startEditing,
              icon: const Icon(
                Icons.edit_outlined,
              ),
              label: const Text(
                'Edit Profile',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: cyan,
                foregroundColor: bg,
                shape: RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(13),
                ),
              ),
            ),
          ),

          const SizedBox(height: 9),

          const Text(
            'You can also tap any editable field to start typing.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: muted,
              fontSize: 11,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed:
            _isSaving ? null : _saveProfile,
            icon: _isSaving
                ? const SizedBox(
              width: 19,
              height: 19,
              child: CircularProgressIndicator(
                color: bg,
                strokeWidth: 2.5,
              ),
            )
                : const Icon(
              Icons.save_outlined,
            ),
            label: Text(
              _isSaving ? 'Saving...' : 'Save Changes',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: cyan,
              foregroundColor: bg,
              shape: RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(13),
              ),
            ),
          ),
        ),

        const SizedBox(height: 10),

        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton.icon(
            onPressed:
            _isSaving ? null : _cancelEditing,
            icon: const Icon(
              Icons.close,
              size: 18,
            ),
            label: const Text('Cancel Changes'),
            style: OutlinedButton.styleFrom(
              foregroundColor: muted,
              side: const BorderSide(color: border),
              shape: RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(13),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ========================================
  // PROFILE CONTENT
  // ========================================

  Widget _buildProfileContent() {
    return Form(
      key: _formKey,
      child: ListView(
        physics:
        const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          18, 15, 18, 35,
        ),
        children: [
          _buildProfileHeader(),

          const SizedBox(height: 20),

          _buildActions(),

          const SizedBox(height: 20),

          _section(
            title: 'Personal Information',
            icon: Icons.person_outline_rounded,
            children: [
              _field(
                label: 'Full Name',
                icon: Icons.badge_outlined,
                controller: _fullNameController,
                maxLength: 120,
              ),
              _field(
                label: 'Username',
                icon: Icons.alternate_email_rounded,
                controller: _usernameController,
                alwaysReadOnly: true,
              ),
              _field(
                label: 'Email Address',
                icon: Icons.email_outlined,
                controller: _emailController,
                keyboardType:
                TextInputType.emailAddress,
                validator: _validateEmail,
              ),
              _field(
                label: 'Mobile Number',
                icon: Icons.phone_android_outlined,
                controller: _mobileController,
                keyboardType:
                TextInputType.phone,
                maxLength: 15,
                validator: _validateMobile,
              ),
              _field(
                label: 'Location',
                icon: Icons.location_on_outlined,
                controller: _locationController,
                maxLength: 120,
              ),
            ],
          ),

          const SizedBox(height: 17),

          _section(
            title: 'Professional Details',
            icon: Icons.work_outline_rounded,
            children: [
              _field(
                label: 'Company / Organization',
                icon: Icons.business_outlined,
                controller: _companyController,
                maxLength: 120,
              ),
              _field(
                label: 'Job Title',
                icon: Icons.work_outline_rounded,
                controller: _jobTitleController,
                maxLength: 100,
              ),
              _field(
                label: 'About Me',
                icon: Icons.description_outlined,
                controller: _bioController,
                maxLines: 4,
                maxLength: 1000,
                keyboardType:
                TextInputType.multiline,
              ),
            ],
          ),

          if (_isEditing) ...[
            const SizedBox(height: 20),
            _buildActions(),
          ],

          const SizedBox(height: 25),

          const Center(
            child: Text(
              'CAMERA CONTROL CENTER',
              style: TextStyle(
                color: muted,
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          const SizedBox(height: 8),

          const Center(
            child: Text(
              'Manage your account information',
              style: TextStyle(
                color: muted,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ========================================
  // MAIN SCREEN
  // ========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text(
          'My Profile',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
        backgroundColor: bg,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Refresh Profile',
            onPressed: _isLoading ||
                _isSaving ||
                _isUploadingImage
                ? null
                : _loadProfile,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
          child: CircularProgressIndicator(
            color: cyan,
          ),
        )
            : _loadError != null
            ? Center(
          child: Padding(
            padding:
            const EdgeInsets.all(25),
            child: Column(
              mainAxisSize:
              MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_outlined,
                  size: 48,
                  color: muted,
                ),
                const SizedBox(height: 15),
                Text(
                  _loadError!,
                  textAlign:
                  TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 15),
                ElevatedButton.icon(
                  onPressed: _loadProfile,
                  icon: const Icon(
                    Icons.refresh,
                  ),
                  label: const Text(
                    'Try Again',
                  ),
                ),
              ],
            ),
          ),
        )
            : Center(
          child: ConstrainedBox(
            constraints:
            const BoxConstraints(
              maxWidth: 640,
            ),
            child: RefreshIndicator(
              color: cyan,
              onRefresh: _loadProfile,
              child: _buildProfileContent(),
            ),
          ),
        ),
      ),
    );
  }
}
