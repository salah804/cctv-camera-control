import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'profile.dart';
import 'change_password.dart';
import 'login.dart';
import 'RecordingScreen.dart';
import 'demo_screen.dart';
import 'web_camera_form.dart';

// ==========================================
// CCTV CAMERA CONTROL
// HOME SCREEN - ANDROID + WEB
// ==========================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ========================================
  // THEME COLORS
  // ========================================

  static const Color _background = Color(0xFF080D18);
  static const Color _surface = Color(0xFF111C2D);
  static const Color _border = Color(0xFF26364B);
  static const Color _cyan = Color(0xFF50D5F5);
  static const Color _muted = Color(0xFF94A8C2);
  static const Color _green = Color(0xFF45E0AD);
  static const Color _red = Color(0xFFFF818D);

  // ========================================
  // BACKEND
  // ========================================

  static const String _logoutUrl =
      'https://salahayash.helioho.st/cctv-api/logout.php';

  final FlutterSecureStorage _secureStorage =
  const FlutterSecureStorage();

  bool _loggingOut = false;

  // ========================================
  // CAMERA STATE
  // ========================================

  List<Map<String, String>> _cameras = [];

  VlcPlayerController? _player;
  int? _activeCameraIndex;
  bool _changingStream = false;

  @override
  void initState() {
    super.initState();
    _loadCameras();
  }

  // ========================================
  // LOAD SAVED CAMERAS
  // ========================================

  Future<void> _loadCameras() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('cameras');

      if (saved == null) return;

      final decoded = jsonDecode(saved);

      if (decoded is! List) return;

      final loaded = <Map<String, String>>[];

      for (final item in decoded) {
        if (item is! Map) continue;

        final name = item['name'];
        final url = item['url'];

        if (name is String &&
            url is String &&
            name.trim().isNotEmpty &&
            url.trim().isNotEmpty) {
          final parsed = Uri.tryParse(url.trim());
          final safeUrl = kIsWeb && parsed != null
              ? parsed.replace(userInfo: '').toString()
              : url.trim();
          loaded.add({
            'name': name.trim(),
            'url': safeUrl,
            if (item['mode'] == 'ip') 'mode': 'ip',
          });
        }
      }

      if (!mounted) return;

      setState(() {
        _cameras = loaded;
      });
    } catch (_) {
      _showMessage('Could not load saved cameras.');
    }
  }

  // ========================================
  // SAVE CAMERAS
  // ========================================

  Future<void> _saveCameras() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // On Web, strip embedded RTSP login credentials before persisting.
      final camerasToSave = kIsWeb
          ? _cameras.map((camera) {
        final parsed = Uri.tryParse(camera['url'] ?? '');
        return <String, String>{
          'name': camera['name'] ?? '',
          'url': parsed == null
              ? (camera['url'] ?? '')
              : parsed.replace(userInfo: '').toString(),
          if (camera['mode'] == 'ip') 'mode': 'ip',
        };
      }).toList()
          : _cameras;

      await prefs.setString('cameras', jsonEncode(camerasToSave));
    } catch (_) {
      _showMessage('Could not save camera changes.');
    }
  }

  // ========================================
  // NOTIFICATIONS
  // ========================================

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _surface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ========================================
  // CAMERA HOST LABEL
  // ========================================

  String _cameraHost(String url) {
    final uri = Uri.tryParse(url);

    if (uri == null || uri.host.isEmpty) {
      return 'RTSP Camera';
    }

    return uri.hasPort
        ? '${uri.host}:${uri.port}'
        : uri.host;
  }

  // ========================================
  // VLC STREAM MANAGEMENT
  // ANDROID ONLY
  // ========================================

  Future<void> _releasePlayer() async {
    final old = _player;

    if (old == null) return;

    if (mounted) {
      setState(() {
        _player = null;
        _activeCameraIndex = null;
      });
    } else {
      _player = null;
      _activeCameraIndex = null;
    }

    try {
      await old.stop();
    } catch (_) {}

    try {
      await old.dispose();
    } catch (_) {}
  }

  // ========================================
  // START CAMERA STREAM
  // ========================================

  Future<void> _startStream(int index) async {
    // A browser can't play raw RTSP. Selecting a Web camera is safe,
    // but streaming will require an authenticated WebRTC/HLS gateway.
    if (kIsWeb) {
      if (index < 0 || index >= _cameras.length) return;
      setState(() => _activeCameraIndex = index);
      _showMessage(
        'Camera selected. Live preview requires a secure '
            'RTSP-to-WebRTC/HLS gateway (not configured yet).',
      );
      return;
    }

    if (_changingStream ||
        index < 0 ||
        index >= _cameras.length) {
      return;
    }

    final url = _cameras[index]['url']!;

    setState(() {
      _changingStream = true;
    });

    try {
      await _releasePlayer();

      if (!mounted) return;

      final controller = VlcPlayerController.network(
        url,
        hwAcc: HwAcc.full,
        autoPlay: true,
        options: VlcPlayerOptions(),
      );

      setState(() {
        _player = controller;
        _activeCameraIndex = index;
      });
    } catch (_) {
      _showMessage(
        'Unable to open the camera stream. '
            'Check its RTSP address and network.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _changingStream = false;
        });
      }
    }
  }

  // ========================================
  // STOP CAMERA STREAM
  // ========================================

  Future<void> _stopStream() async {
    if (kIsWeb) {
      if (mounted) setState(() => _activeCameraIndex = null);
      return;
    }

    if (_changingStream || _player == null) return;

    setState(() {
      _changingStream = true;
    });

    try {
      await _releasePlayer();
    } finally {
      if (mounted) {
        setState(() {
          _changingStream = false;
        });
      }
    }
  }

  // ========================================
  // NAVIGATION
  // ========================================

  void _openRecordings() {
    // Web users open simulated recordings.
    if (kIsWeb) {
      _openDemo();
      return;
    }

    // Android behavior remains unchanged.
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const RecordingScreen(),
      ),
    );
  }

  void _openDemo() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const DemoScreen(),
      ),
    );
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Profile(),
      ),
    );
  }

  // ========================================
  // SECURE LOGOUT
  // ========================================

  Future<void> _logout() async {
    if (_loggingOut) return;

    setState(() {
      _loggingOut = true;
    });

    try {
      // Read the saved PHP session token.
      final token = await _secureStorage.read(
        key: 'session_token',
      );

      // Revoke the server-side session.
      if (token != null && token.isNotEmpty) {
        final response = await http.post(
          Uri.parse(_logoutUrl),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: {
            'probe': '1',
          },
        ).timeout(
          const Duration(seconds: 15),
        );

        debugPrint(
          'Logout HTTP status: ${response.statusCode}',
        );

        if (response.statusCode != 200 &&
            response.statusCode != 401) {
          throw StateError(
            'Server could not revoke session.',
          );
        }

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);

          if (decoded is! Map ||
              decoded['success'] != true) {
            throw StateError(
              'Logout was not confirmed.',
            );
          }
        }
      }

      // Stop any active Android camera stream.
      await _releasePlayer();

      // Sign out of Google locally.
      // A failed SDK sign-out must not leave
      // the PHP session active.
      try {
        await GoogleSignIn().signOut();
      } catch (_) {
        debugPrint(
          'Google SDK sign-out was unsuccessful.',
        );
      }

      // Clear the app session.
      await _secureStorage.delete(
        key: 'session_token',
      );

      final prefs = await SharedPreferences.getInstance();

      await prefs.remove('username');
      await prefs.remove('auth_method');

      if (!mounted) return;

      // Return to login.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const LoginScreen(),
        ),
            (route) => false,
      );
    } catch (e) {
      debugPrint(
        'Secure logout failed: ${e.runtimeType}',
      );

      _showMessage(
        'Could not log out securely. '
            'Check your connection and PHP server.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _loggingOut = false;
        });
      }
    }
  }

  // ========================================
  // ADD / EDIT CAMERA
  // ========================================

  Future<void> _showCameraForm({
    int? editingIndex,
  }) async {
    // Web has its own form. Android's RTSP/VLC form is left unchanged.
    if (kIsWeb) {
      if (editingIndex != null &&
          (editingIndex < 0 || editingIndex >= _cameras.length)) {
        return;
      }
      final updated = await showWebCameraForm(
        context,
        initial: editingIndex == null ? null : _cameras[editingIndex],
      );
      if (!mounted || updated == null) return;
      setState(() {
        if (editingIndex != null) {
          _cameras[editingIndex] = updated;
          if (_activeCameraIndex == editingIndex) {
            _activeCameraIndex = null;
          }
        } else {
          _cameras.add(updated);
        }
      });
      await _saveCameras();
      if (!mounted) return;
      _showMessage(
        'Camera configuration saved locally. '
            'Live preview needs a streaming gateway.',
      );
      return;
    }

    final editing = editingIndex != null;

    if (editingIndex != null &&
        (editingIndex < 0 ||
            editingIndex >= _cameras.length)) {
      return;
    }

    final initial = editingIndex == null
        ? null
        : _cameras[editingIndex];

    final formKey = GlobalKey<FormState>();

    String cameraName = initial?['name'] ?? '';
    String cameraUrl = initial?['url'] ?? '';

    final updated =
    await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext)
                .viewInsets
                .bottom,
          ),
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                22,
                18,
                22,
                28,
              ),
              decoration: const BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _muted.withOpacity(0.5),
                          borderRadius:
                          BorderRadius.circular(10),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Header.
                    Row(
                      children: [
                        const Icon(
                          Icons.add_a_photo_outlined,
                          color: _cyan,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            editing
                                ? 'Edit Camera'
                                : 'Add IP Camera',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            FocusScope.of(
                              sheetContext,
                            ).unfocus();

                            Navigator.of(
                              sheetContext,
                            ).pop();
                          },
                          icon: const Icon(
                            Icons.close,
                            color: _muted,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    const Text(
                      'Connect your IP camera using '
                          'its RTSP streaming address.',
                      style: TextStyle(
                        color: _muted,
                        height: 1.5,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Camera name.
                    TextFormField(
                      initialValue: cameraName,
                      style: const TextStyle(
                        color: Colors.white,
                      ),
                      textCapitalization:
                      TextCapitalization.words,
                      decoration: _fieldDecoration(
                        'Camera Name',
                        Icons.videocam_outlined,
                        hint: 'e.g. Front Entrance',
                      ),
                      validator: (value) {
                        if (value == null ||
                            value.trim().isEmpty) {
                          return 'Enter a camera name';
                        }
                        return null;
                      },
                      onSaved: (value) {
                        cameraName = value?.trim() ?? '';
                      },
                    ),

                    const SizedBox(height: 16),

                    // RTSP URL.
                    TextFormField(
                      initialValue: cameraUrl,
                      style: const TextStyle(
                        color: Colors.white,
                      ),
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: _fieldDecoration(
                        'RTSP URL',
                        Icons.link_rounded,
                        hint:
                        'rtsp://camera-host:554/stream',
                      ),
                      validator: (value) {
                        final input = value?.trim() ?? '';
                        final uri = Uri.tryParse(input);

                        if (uri == null ||
                            (uri.scheme.toLowerCase() !=
                                'rtsp' &&
                                uri.scheme.toLowerCase() !=
                                    'rtsps') ||
                            uri.host.isEmpty ||
                            input.contains(' ')) {
                          return 'Enter a valid RTSP URL';
                        }

                        return null;
                      },
                      onSaved: (value) {
                        cameraUrl = value?.trim() ?? '';
                      },
                    ),

                    const SizedBox(height: 16),

                    // Storage notice.
                    const Row(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          color: _muted,
                          size: 18,
                        ),
                        SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'Camera URLs are currently '
                                'saved locally.',
                            style: TextStyle(
                              color: _muted,
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 25),

                    // Save.
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          final form =
                              formKey.currentState;

                          if (form == null ||
                              !form.validate()) {
                            return;
                          }

                          form.save();

                          FocusScope.of(
                            sheetContext,
                          ).unfocus();

                          Navigator.of(
                            sheetContext,
                          ).pop({
                            'name': cameraName,
                            'url': cameraUrl,
                          });
                        },
                        icon: Icon(
                          editing
                              ? Icons.save_outlined
                              : Icons.add_circle_outline,
                        ),
                        label: Text(
                          editing
                              ? 'Save Changes'
                              : 'Add Camera',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: _cyan,
                          foregroundColor: _background,
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
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
            ),
          ),
        );
      },
    );

    if (!mounted || updated == null) {
      return;
    }

    final activeEdit = editing &&
        _activeCameraIndex == editingIndex;

    setState(() {
      if (editingIndex != null) {
        _cameras[editingIndex] = updated;
      } else {
        _cameras.add(updated);
      }
    });

    await _saveCameras();

    if (!mounted) return;

    if (activeEdit) {
      await _stopStream();
    }

    if (!mounted) return;

    _showMessage(
      editing
          ? 'Camera updated.'
          : 'Camera added successfully.',
    );
  }

  // ========================================
  // CAMERA FIELD DESIGN
  // ========================================

  InputDecoration _fieldDecoration(
      String label,
      IconData icon, {
        String? hint,
      }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(
        icon,
        color: _cyan,
      ),
      labelStyle: const TextStyle(
        color: _muted,
      ),
      hintStyle: TextStyle(
        color: _muted.withOpacity(0.55),
      ),
      filled: true,
      fillColor: _background,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 17,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: _cyan,
          width: 1.6,
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
          width: 1.6,
        ),
      ),
    );
  }

  // ========================================
  // DELETE CAMERA
  // ========================================

  Future<void> _deleteCamera(int index) async {
    final name = _cameras[index]['name']!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _surface,
          title: const Text(
            'Remove Camera?',
            style: TextStyle(
              color: Colors.white,
            ),
          ),
          content: Text(
            'Remove "$name" from your saved cameras?',
            style: const TextStyle(
              color: _muted,
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

    if (_activeCameraIndex == index) {
      await _stopStream();

      if (!mounted) return;
    } else if (_activeCameraIndex != null &&
        _activeCameraIndex! > index) {
      setState(() {
        _activeCameraIndex = _activeCameraIndex! - 1;
      });
    }

    setState(() {
      _cameras.removeAt(index);
    });

    await _saveCameras();

    _showMessage('Camera removed.');
  }

  // ========================================
  // HOME SCREEN
  // ========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: const Row(
          children: [
            Icon(
              Icons.shield_outlined,
              color: _cyan,
              size: 23,
            ),
            SizedBox(width: 9),
            Text(
              'CAMERA CONTROL',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Profile',
            onPressed: _openProfile,
            icon: const CircleAvatar(
              radius: 18,
              backgroundColor: _surface,
              child: Icon(
                Icons.person_outline,
                color: _cyan,
                size: 21,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: _buildDrawer(),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 850;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                18,
                18,
                18,
                40,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 1150,
                  ),
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                    children: [
                      _buildHero(),
                      const SizedBox(height: 24),

                      if (wide)
                        Row(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 6,
                              child: _buildPreviewPanel(),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              flex: 5,
                              child: _buildCamerasPanel(),
                            ),
                          ],
                        )
                      else ...[
                        _buildPreviewPanel(),
                        const SizedBox(height: 22),
                        _buildCamerasPanel(),
                      ],

                      const SizedBox(height: 24),

                      Center(
                        child: Text(
                          'SECURE YOUR SPACE  •  '
                              'MONITOR WITH CONFIDENCE',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _muted.withOpacity(
                              0.75,
                            ),
                            fontSize: 10,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ========================================
  // HERO SECTION
  // ========================================

  Widget _buildHero() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _cyan.withValues(alpha: 0.22),
        ),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF173D55),
            Color(0xFF11243A),
            Color(0xFF111827),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_outlined,
                color: _cyan,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'SMART MONITORING WORKSPACE',
                style: TextStyle(
                  color: _cyan.withValues(alpha: 0.75),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          Text(
            kIsWeb
                ? 'Explore CCTV.\nRight in your browser.'
                : 'Your cameras.\nOne control center.',
            style: const TextStyle(
              fontSize: 27,
              height: 1.15,
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            kIsWeb
                ? 'Add cameras using an RTSP URL or IP address. '
                'Live browser video requires a secure gateway.'
                : 'Connect your own IP cameras, '
                'view live streams, and access recordings.',
            style: const TextStyle(
              color: Color(0xFFC2D5E4),
              height: 1.5,
            ),
          ),

          const SizedBox(height: 22),

          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => _showCameraForm(),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Add Camera'),
                style: FilledButton.styleFrom(
                  backgroundColor: _cyan,
                  foregroundColor: _background,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(12),
                  ),
                ),
              ),

              OutlinedButton.icon(
                onPressed: _openRecordings,
                icon: const Icon(
                  Icons.video_library_outlined,
                  size: 19,
                ),
                label: Text(
                  kIsWeb
                      ? 'Demo Recordings'
                      : 'Recordings',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: Colors.white.withOpacity(
                      0.27,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(12),
                  ),
                ),
              ),

              OutlinedButton.icon(
                onPressed: _openDemo,
                icon: const Icon(
                  Icons.smart_display_outlined,
                  size: 19,
                ),
                label: const Text('Try Demo'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _cyan,
                  side: const BorderSide(
                    color: _cyan,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          Wrap(
            spacing: 20,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.storage_outlined,
                    color: _cyan,
                    size: 17,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_cameras.length} saved '
                        '${_cameras.length == 1 ? 'camera' : 'cameras'}',
                    style: const TextStyle(
                      color: Color(0xFFD6E5F0),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),

              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    kIsWeb
                        ? Icons.language
                        : _player != null
                        ? Icons.circle
                        : Icons.circle_outlined,
                    color: kIsWeb
                        ? _green
                        : _player != null
                        ? _green
                        : _muted,
                    size: kIsWeb ? 16 : 11,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    kIsWeb
                        ? 'RTSP gateway needed'
                        : _player != null
                        ? 'Stream selected'
                        : 'No active stream',
                    style: const TextStyle(
                      color: Color(0xFFD6E5F0),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ========================================
  // WEB BROWSER PREVIEW PANEL
  // ========================================

  Widget _buildBrowserPreviewPanel() {
    final selected = _activeCameraIndex != null &&
        _activeCameraIndex! < _cameras.length
        ? _cameras[_activeCameraIndex!]
        : null;

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.live_tv_outlined,
                color: _cyan,
                size: 21,
              ),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Camera Preview',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF02060D),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
            ),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment:
                  MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.smart_display_outlined,
                      color: _cyan,
                      size: 42,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      selected == null
                          ? 'No camera selected'
                          : selected['name'] ?? 'Camera selected',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      selected == null
                          ? 'Add or select a camera, or try Demo Mode'
                          : 'Configuration saved. Live gateway pending.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 17),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _openDemo,
              icon: const Icon(
                Icons.play_circle_outline,
              ),
              label: const Text('Open CCTV Demo'),
              style: FilledButton.styleFrom(
                backgroundColor: _cyan,
                foregroundColor: _background,
                padding: const EdgeInsets.symmetric(
                  vertical: 15,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          const Text(
            'Real RTSP cameras need a secure WebRTC/HLS gateway '
                'before they can play in a browser. '
                'Demo Mode uses sample footage.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _muted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ========================================
  // LIVE CAMERA PREVIEW
  // ========================================

  Widget _buildPreviewPanel() {
    if (kIsWeb) {
      return _buildBrowserPreviewPanel();
    }

    final controller = _player;

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.live_tv_outlined,
                color: _cyan,
                size: 21,
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Live Preview',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),

              if (controller != null)
                ValueListenableBuilder<VlcPlayerValue>(
                  valueListenable: controller,
                  builder: (context, value, child) {
                    final label = value.hasError
                        ? 'ERROR'
                        : value.isPlaying
                        ? 'LIVE'
                        : value.isBuffering
                        ? 'BUFFERING'
                        : 'CONNECTING';

                    final color = value.hasError
                        ? Colors.redAccent
                        : value.isPlaying
                        ? _green
                        : _cyan;

                    return _pill(
                      label,
                      color: color,
                    );
                  },
                )
              else
                _pill(
                  'STANDBY',
                  color: _muted,
                ),
            ],
          ),

          const SizedBox(height: 18),

          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              color: const Color(0xFF02060D),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: controller == null
                    ? const Column(
                  mainAxisAlignment:
                  MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.videocam_off_outlined,
                      color: _muted,
                      size: 49,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No camera selected',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Choose a saved camera '
                          'below to begin',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                )
                    : VlcPlayer(
                  controller: controller,
                  aspectRatio: 16 / 9,
                  placeholder: const Center(
                    child: CircularProgressIndicator(
                      color: _cyan,
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 17),

          if (controller != null) ...[
            Text(
              _activeCameraIndex != null &&
                  _activeCameraIndex! < _cameras.length
                  ? _cameras[_activeCameraIndex!]['name']!
                  : 'Active camera',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),

            const SizedBox(height: 11),

            ValueListenableBuilder<VlcPlayerValue>(
              valueListenable: controller,
              builder: (context, value, child) {
                if (!value.hasError) {
                  return const SizedBox.shrink();
                }

                return const Text(
                  'Could not play this stream. '
                      'Check its URL, permissions, and network.',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12,
                  ),
                );
              },
            ),

            const SizedBox(height: 7),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed:
                _changingStream ? null : _stopStream,
                icon: const Icon(
                  Icons.stop_circle_outlined,
                ),
                label: const Text('Stop Stream'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _red,
                  side: const BorderSide(
                    color: Color(0xFF743C4B),
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ] else
            const Text(
              'RTSP video is played locally '
                  'on your Android device using VLC.',
              style: TextStyle(
                color: _muted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
        ],
      ),
    );
  }

  // ========================================
  // SAVED CAMERAS PANEL
  // ========================================

  Widget _buildCamerasPanel() {
    // Shared camera-management panel for Android and Web.
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.grid_view_rounded,
                color: _cyan,
                size: 21,
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'My Cameras',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Add a camera',
                onPressed: () => _showCameraForm(),
                icon: const Icon(
                  Icons.add_circle_outline,
                  color: _cyan,
                ),
              ),
            ],
          ),

          const SizedBox(height: 5),

          Text(
            '${_cameras.length} configured '
                '${_cameras.length == 1 ? 'camera' : 'cameras'}',
            style: const TextStyle(
              color: _muted,
              fontSize: 12,
            ),
          ),

          if (kIsWeb) ...[
            const SizedBox(height: 10),
            const Text(
              'Add an RTSP URL or IP camera configuration. '
                  'Live browser playback will be enabled after '
                  'connecting a secure WebRTC/HLS gateway.',
              style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
            ),
          ],

          const SizedBox(height: 18),

          if (_cameras.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 36,
              ),
              decoration: BoxDecoration(
                color: _background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _border),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.add_to_photos_outlined,
                    color: _cyan.withValues(alpha: 0.22),
                    size: 42,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No cameras added yet',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    kIsWeb
                        ? 'Add an RTSP URL or IP address to configure a camera.'
                        : 'Add an RTSP address to start watching.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            )
          else
            ...List.generate(
              _cameras.length,
                  (index) => _cameraCard(index),
            ),
        ],
      ),
    );
  }

  // ========================================
  // CAMERA CARD
  // ========================================

  Widget _cameraCard(int index) {
    final camera = _cameras[index];
    final active = _activeCameraIndex == index;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: active
            ? const Color(0xFF19394A)
            : _background,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: _changingStream
              ? null
              : () => _startStream(index),
          borderRadius: BorderRadius.circular(15),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: active
                    ? _cyan.withOpacity(0.65)
                    : _border,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _cyan.withValues(alpha: 0.22),
                    borderRadius:
                    BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.videocam_outlined,
                    color: _cyan,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        camera['name']!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _cameraHost(camera['url']!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                Icon(
                  kIsWeb && active
                      ? Icons.check_circle_outline
                      : active
                      ? Icons.graphic_eq
                      : Icons.play_circle_outline,
                  color: _cyan,
                  size: active ? 21 : 24,
                ),

                PopupMenuButton<String>(
                  tooltip: 'Camera options',
                  color: _surface,
                  icon: const Icon(
                    Icons.more_vert,
                    color: _muted,
                  ),
                  onSelected: (choice) {
                    if (choice == 'edit') {
                      _showCameraForm(
                        editingIndex: index,
                      );
                    } else if (choice == 'delete') {
                      _deleteCamera(index);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(
                        'Edit Camera',
                        style: TextStyle(
                          color: Colors.white,
                        ),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'Remove Camera',
                        style: TextStyle(
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ========================================
  // REUSABLE PANEL
  // ========================================

  Widget _panel({
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _border,
        ),
      ),
      child: child,
    );
  }

  // ========================================
  // STATUS LABEL
  // ========================================

  Widget _pill(
      String label, {
        required Color color,
      }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        border: Border.all(
          color: color.withOpacity(0.28),
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 10,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  // ========================================
  // NAVIGATION DRAWER
  // ========================================

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: _surface,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                24,
                33,
                24,
                28,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF18455F),
                    _surface,
                  ],
                ),
              ),
              child: const Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    color: _cyan,
                    size: 37,
                  ),
                  SizedBox(height: 15),
                  Text(
                    'CAMERA CONTROL',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Monitoring workspace',
                    style: TextStyle(
                      color: _muted,
                    ),
                  ),
                ],
              ),
            ),

            ListTile(
              leading: const Icon(
                Icons.person_outline,
                color: _cyan,
              ),
              title: const Text(
                'Profile',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _openProfile();
              },
            ),

            ListTile(
              leading: const Icon(
                Icons.password_outlined,
                color: _cyan,
              ),
              title: const Text(
                'Change Password',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);

                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ChangePasswordScreen(),
                  ),
                );
              },
            ),

            ListTile(
              leading: const Icon(
                Icons.video_library_outlined,
                color: _cyan,
              ),
              title: const Text(
                'Recordings',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _openRecordings();
              },
            ),

            ListTile(
              leading: const Icon(
                Icons.smart_display_outlined,
                color: _cyan,
              ),
              title: const Text(
                'Demo Mode',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Try without an IP camera',
                style: TextStyle(
                  color: _muted,
                  fontSize: 11,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _openDemo();
              },
            ),

            const Spacer(),
            const Divider(color: _border),

            ListTile(
              leading: const Icon(
                Icons.logout,
                color: _red,
              ),
              title: const Text(
                'Logout',
                style: TextStyle(color: Colors.white),
              ),
              trailing: _loggingOut
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _cyan,
                ),
              )
                  : null,
              onTap: _loggingOut
                  ? null
                  : () {
                Navigator.pop(context);
                _logout();
              },
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ========================================
  // CLEANUP
  // ========================================

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }
}
