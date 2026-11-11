import 'package:flutter/material.dart';

/// Web-only configuration form for an RTSP camera.
///
/// This does NOT establish a live stream. Browsers require an authenticated
/// WebRTC/HLS gateway for RTSP playback. Credentials are never saved here.
Future<Map<String, String>?> showWebCameraForm(
    BuildContext context, {
      Map<String, String>? initial,
    }) {
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _WebCameraFormSheet(initial: initial),
  );
}

class _WebCameraFormSheet extends StatefulWidget {
  const _WebCameraFormSheet({this.initial});

  final Map<String, String>? initial;

  @override
  State<_WebCameraFormSheet> createState() => _WebCameraFormSheetState();
}

class _WebCameraFormSheetState extends State<_WebCameraFormSheet> {
  static const _background = Color(0xFF080D18);
  static const _surface = Color(0xFF111C2D);
  static const _border = Color(0xFF26364B);
  static const _cyan = Color(0xFF50D5F5);
  static const _muted = Color(0xFF94A8C2);

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _path;
  late final TextEditingController _username;
  late final TextEditingController _password;

  bool _useIp = false;

  @override
  void initState() {
    super.initState();
    final saved = widget.initial ?? const <String, String>{};
    final parsed = Uri.tryParse(saved['url'] ?? '');

    _useIp = saved['mode'] == 'ip';
    _name = TextEditingController(text: saved['name'] ?? '');
    _url = TextEditingController(text: saved['url'] ?? '');
    _host = TextEditingController(text: parsed?.host ?? '');
    _port = TextEditingController(
      text: parsed != null && parsed.hasPort
          ? parsed.port.toString()
          : '554',
    );
    _path = TextEditingController(
      text: (parsed?.path ?? '') +
          (parsed != null && parsed.hasQuery ? '?${parsed.query}' : ''),
    );

    // Deliberately never pre-fill or persist credentials.
    _username = TextEditingController();
    _password = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _host.dispose();
    _port.dispose();
    _path.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: _muted),
      hintStyle: const TextStyle(color: _muted),
      filled: true,
      fillColor: _background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _cyan),
      ),
      errorMaxLines: 3,
    );
  }

  String? _validateUrl(String? value) {
    final raw = (value ?? '').trim();
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        (uri.scheme.toLowerCase() != 'rtsp' &&
            uri.scheme.toLowerCase() != 'rtsps') ||
        uri.host.isEmpty ||
        raw.contains(RegExp(r'\s')) ||
        uri.hasFragment) {
      return 'Enter a valid rtsp:// or rtsps:// URL';
    }
    if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) {
      return 'Invalid RTSP port';
    }
    if (_containsSecretQuery(uri)) {
      return 'Remove passwords or access tokens from URL parameters';
    }
    return null;
  }

  bool _containsSecretQuery(Uri uri) {
    const secretKeys = <String>{
      'password',
      'passwd',
      'pass',
      'pwd',
      'token',
      'access_token',
      'api_key',
      'apikey',
      'secret',
      'auth',
    };
    return uri.queryParameters.keys
        .any((key) => secretKeys.contains(key.toLowerCase()));
  }

  String? _validateHost(String? value) {
    final host = (value ?? '').trim();
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9.-]*$').hasMatch(host) ||
        host.contains('..')) {
      return 'Enter an IPv4 address or hostname (without http://)';
    }
    return null;
  }

  String? _validatePort(String? value) {
    final port = int.tryParse((value ?? '').trim());
    if (port == null || port < 1 || port > 65535) {
      return 'Port must be between 1 and 65535';
    }
    return null;
  }

  String? _validatePath(String? value) {
    final path = (value ?? '').trim();
    if (path.isEmpty || path.contains(RegExp(r'\s')) || path.contains('#')) {
      return 'Enter the RTSP stream path';
    }
    final candidate = Uri.tryParse('rtsp://camera.local:554/' +
        (path.startsWith('/') ? path.substring(1) : path));
    if (candidate == null || _containsSecretQuery(candidate)) {
      return 'Do not include passwords or tokens in the stream path';
    }
    return null;
  }

  void _save() {
    if (_formKey.currentState?.validate() != true) return;

    late final Uri uri;
    if (_useIp) {
      final host = _host.text.trim();
      final port = int.parse(_port.text.trim());
      final path = _path.text.trim();
      final normalizedPath = path.startsWith('/') ? path : '/$path';
      uri = Uri.parse('rtsp://$host:$port$normalizedPath');
    } else {
      uri = Uri.parse(_url.text.trim());
    }

    // Strip embedded username/password from RTSP URLs. Never store the
    // separate username/password fields in browser SharedPreferences.
    final safeUrl = uri.replace(userInfo: '').toString();
    Navigator.of(context).pop(<String, String>{
      'name': _name.text.trim(),
      'url': safeUrl,
      'mode': _useIp ? 'ip' : 'rtsp',
    });
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final editing = widget.initial != null;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.88,
            ),
            decoration: const BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.add_a_photo_outlined, color: _cyan),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            editing ? 'Edit Camera' : 'Add Real Camera',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, color: _muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _name,
                      style: const TextStyle(color: Colors.white),
                      textCapitalization: TextCapitalization.words,
                      decoration: _decoration(
                        'Camera name',
                        hint: 'Front gate',
                      ),
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? 'Enter a camera name'
                          : null,
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Connection method',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 9,
                      children: [
                        ChoiceChip(
                          label: const Text('RTSP URL'),
                          selected: !_useIp,
                          onSelected: (_) => setState(() => _useIp = false),
                        ),
                        ChoiceChip(
                          label: const Text('IP / Hostname'),
                          selected: _useIp,
                          onSelected: (_) => setState(() => _useIp = true),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (!_useIp)
                      TextFormField(
                        controller: _url,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: _decoration(
                          'RTSP URL',
                          hint: 'rtsp://192.168.1.100:554/stream1',
                        ),
                        validator: _validateUrl,
                      )
                    else ...[
                      TextFormField(
                        controller: _host,
                        style: const TextStyle(color: Colors.white),
                        autocorrect: false,
                        decoration: _decoration(
                          'Camera IP address or hostname',
                          hint: '192.168.1.100',
                        ),
                        validator: _validateHost,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _port,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.number,
                        decoration: _decoration('RTSP port', hint: '554'),
                        validator: _validatePort,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _path,
                        style: const TextStyle(color: Colors.white),
                        autocorrect: false,
                        decoration: _decoration(
                          'RTSP stream path',
                          hint: '/cam/realmonitor?channel=1&subtype=0',
                        ),
                        validator: _validatePath,
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Text(
                      'Camera username & password (optional, session only)',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    const SizedBox(height: 9),
                    TextFormField(
                      controller: _username,
                      style: const TextStyle(color: Colors.white),
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: _decoration('Username', hint: 'admin'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _password,
                      style: const TextStyle(color: Colors.white),
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: _decoration('Password'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Configuration only: live RTSP video needs a secure '
                          'WebRTC/HLS gateway. Camera usernames and passwords '
                          'are not saved or sent anywhere. You will enter them '
                          'again after the gateway is connected. Avoid putting '
                          'credentials in the RTSP URL.',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: _cyan,
                        foregroundColor: _background,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: const Icon(Icons.save_outlined),
                      label: Text(editing ? 'Save Changes' : 'Save Camera'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
