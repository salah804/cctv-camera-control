
import 'dart:convert';
import 'playback_screen.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'playback_screen.dart';

// Match the futuristic theme used in home.dart.
class _RecordingTheme {
  static const background = Color(0xFF080D18);
  static const surface = Color(0xFF111C2D);
  static const border = Color(0xFF26364B);
  static const cyan = Color(0xFF50D5F5);
  static const muted = Color(0xFF94A8C2);
}

// Camera configuration loaded from the Home dashboard.
class _SavedCamera {
  const _SavedCamera({
    required this.name,
    required this.streamUri,
  });

  final String name;
  final Uri streamUri;

  String get hostLabel => streamUri.hasPort
      ? '${streamUri.host}:${streamUri.port}'
      : streamUri.host;

  // Dahua camera channels normally start at 1.
  int get channel {
    final raw = streamUri.queryParameters['channel'];
    final parsed = raw == null ? null : int.tryParse(raw);

    return parsed != null && parsed > 0 ? parsed : 1;
  }

  // Generate a Dahua-compatible playback URL.
  String playbackUrl(DateTime start, DateTime end) {
    final format = DateFormat('yyyy_MM_dd_HH_mm_ss');

    // Keep the original camera connection details.
    // Change only the path and recording time parameters.
    //
    // Never print this URL because it may contain credentials.
    return streamUri
        .replace(
      path: '/cam/playback',
      queryParameters: {
        'channel': channel.toString(),
        'starttime': format.format(start),
        'endtime': format.format(end),
      },
      fragment: '',
    )
        .toString();
  }
}

// Main recordings page.
class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() =>
      _RecordingScreenState();
}

class _RecordingScreenState
    extends State<RecordingScreen> {
  final List<_SavedCamera> _cameras = [];

  DateTime _selectedDate = DateTime.now();

  int? _selectedCameraIndex;

  bool _loading = true;

  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadSavedCameras();
  }

  // Load the same cameras saved by home.dart.
  Future<void> _loadSavedCameras() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final prefs =
      await SharedPreferences.getInstance();

      final saved = prefs.getString('cameras');

      final decoded = saved == null
          ? <dynamic>[]
          : jsonDecode(saved);

      if (decoded is! List) {
        throw const FormatException(
          'Saved cameras have an invalid format.',
        );
      }

      final loaded = <_SavedCamera>[];

      for (final item in decoded) {
        if (item is! Map) continue;

        final name = item['name'];
        final url = item['url'];

        if (name is! String || url is! String) {
          continue;
        }

        final uri = Uri.tryParse(url.trim());

        if (name.trim().isEmpty ||
            uri == null ||
            !['rtsp', 'rtsps']
                .contains(uri.scheme.toLowerCase()) ||
            uri.host.isEmpty) {
          continue;
        }

        loaded.add(
          _SavedCamera(
            name: name.trim(),
            streamUri: uri,
          ),
        );
      }

      if (!mounted) return;

      setState(() {
        _cameras
          ..clear()
          ..addAll(loaded);

        _selectedCameraIndex =
        loaded.isEmpty ? null : 0;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loadError = 'Unable to load saved cameras.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // Date picker.
  Future<void> _pickDate() async {
    final now = DateTime.now();

    final initial = _selectedDate.isAfter(now)
        ? now
        : _selectedDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: _RecordingTheme.cyan,
              onPrimary: _RecordingTheme.background,
              surface: _RecordingTheme.surface,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  // Open generated playback time ranges.
  void _viewPlaybackOptions() {
    final index = _selectedCameraIndex;

    if (index == null ||
        index < 0 ||
        index >= _cameras.length) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => _PlaybackOptionsPage(
          camera: _cameras[index],
          selectedDate: _selectedDate,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _RecordingTheme.background,

      appBar: AppBar(
        backgroundColor: _RecordingTheme.background,
        foregroundColor: Colors.white,
        title: const Text(
          'Recordings',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh cameras',
            onPressed:
            _loading ? null : _loadSavedCameras,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            20,
            18,
            20,
            32,
          ),
          children: [
            // Page introduction.
            const _IntroCard(
              icon: Icons.video_library_outlined,
              title: 'Recording Center',
              subtitle:
              'Choose one of your saved cameras and '
                  'a date to try Dahua-compatible playback.',
            ),

            const SizedBox(height: 24),

            const _SectionTitle(
              '01',
              'Select Camera',
            ),

            const SizedBox(height: 12),

            if (_loading)
              const _StateCard(
                icon: Icons.hourglass_top,
                message: 'Loading saved cameras...',
              )
            else if (_loadError != null)
              _StateCard(
                icon: Icons.error_outline,
                message: _loadError!,
              )
            else if (_cameras.isEmpty)
                const _StateCard(
                  icon: Icons.videocam_off_outlined,
                  message:
                  'No saved cameras found. '
                      'Return to the dashboard and '
                      'add an RTSP camera first.',
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                  ),
                  decoration: _panelDecoration(),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      dropdownColor:
                      _RecordingTheme.surface,
                      value: _selectedCameraIndex,
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: _RecordingTheme.cyan,
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      items: [
                        for (
                        int i = 0;
                        i < _cameras.length;
                        i++
                        )
                          DropdownMenuItem<int>(
                            value: i,
                            child: Text(
                              '${_cameras[i].name}  •  '
                                  '${_cameras[i].hostLabel}',
                              overflow:
                              TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedCameraIndex = value;
                        });
                      },
                    ),
                  ),
                ),

            const SizedBox(height: 25),

            const _SectionTitle(
              '02',
              'Choose Date',
            ),

            const SizedBox(height: 12),

            InkWell(
              borderRadius:
              BorderRadius.circular(17),
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: _panelDecoration(),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_month_outlined,
                      color: _RecordingTheme.cyan,
                      size: 25,
                    ),

                    const SizedBox(width: 16),

                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Playback date',
                            style: TextStyle(
                              fontSize: 12,
                              color:
                              _RecordingTheme.muted,
                            ),
                          ),

                          const SizedBox(height: 5),

                          Text(
                            DateFormat(
                              'EEEE, dd MMMM yyyy',
                            ).format(_selectedDate),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight:
                              FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Icon(
                      Icons.edit_calendar_outlined,
                      color: _RecordingTheme.muted,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 26),

            // Main action button.
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed:
                _selectedCameraIndex == null
                    ? null
                    : _viewPlaybackOptions,
                style: FilledButton.styleFrom(
                  backgroundColor:
                  _RecordingTheme.cyan,
                  foregroundColor:
                  _RecordingTheme.background,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(
                  Icons.playlist_play_rounded,
                ),
                label: const Text(
                  'View Playback Options',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 18),

            const _InfoNote(
              'This screen generates playback time '
                  'ranges; it does not search the camera '
                  'or confirm that recordings exist. '
                  'Playback works only if the camera/NVR '
                  'supports Dahua-style recording access '
                  'and has footage stored for that time.',
            ),
          ],
        ),
      ),
    );
  }
}

// A playback time range.
class _PlaybackOption {
  const _PlaybackOption({
    required this.label,
    required this.start,
    required this.end,
  });

  final String label;
  final DateTime start;
  final DateTime end;
}

// Page containing full-day and 2-hour playback options.
class _PlaybackOptionsPage extends StatelessWidget {
  const _PlaybackOptionsPage({
    required this.camera,
    required this.selectedDate,
  });

  final _SavedCamera camera;
  final DateTime selectedDate;

  List<_PlaybackOption> _options() {
    final year = selectedDate.year;
    final month = selectedDate.month;
    final day = selectedDate.day;

    final options = <_PlaybackOption>[
      _PlaybackOption(
        label: 'Full day • 00:00 – 23:59',
        start: DateTime(
          year,
          month,
          day,
        ),
        end: DateTime(
          year,
          month,
          day,
          23,
          59,
          59,
        ),
      ),
    ];

    // Generate two-hour playback windows.
    for (
    int hour = 0;
    hour < 24;
    hour += 2
    ) {
      final start = DateTime(
        year,
        month,
        day,
        hour,
      );

      final end = DateTime(
        year,
        month,
        day,
        hour + 1,
        59,
        59,
      );

      final label =
          '${DateFormat('HH:mm').format(start)}'
          ' – '
          '${DateFormat('HH:mm').format(end)}';

      options.add(
        _PlaybackOption(
          label: label,
          start: start,
          end: end,
        ),
      );
    }

    return options;
  }

  // Pass the generated URL to the existing VLC page.
  void _play(
      BuildContext context,
      _PlaybackOption option,
      ) {
    final url = camera.playbackUrl(
      option.start,
      option.end,
    );

    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => VideoPlaybackScreen(
          playbackUrl: url,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final options = _options();

    return Scaffold(
      backgroundColor: _RecordingTheme.background,

      appBar: AppBar(
        backgroundColor: _RecordingTheme.background,
        foregroundColor: Colors.white,
        title: const Text(
          'Playback Options',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),

      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          20,
          18,
          20,
          30,
        ),
        children: [
          _IntroCard(
            icon: Icons.history_rounded,
            title: camera.name,
            subtitle:
            '${camera.hostLabel}  •  '
                'Channel ${camera.channel}\n'
                '${DateFormat('dd MMM yyyy').format(selectedDate)}',
          ),

          const SizedBox(height: 18),

          const _InfoNote(
            'Tap a time range to attempt playback. '
                'These are generated time windows, not '
                'a verified recording list. '
                'The camera must be reachable and contain '
                'recordings for the chosen time. '
                'Check the camera clock/timezone '
                'if playback is offset.',
          ),

          const SizedBox(height: 24),

          const _SectionTitle(
            '▶',
            'Try Playback',
          ),

          const SizedBox(height: 12),

          for (
          int index = 0;
          index < options.length;
          index++
          ) ...[
            Container(
              margin: const EdgeInsets.only(
                bottom: 10,
              ),
              decoration: _panelDecoration(),
              child: ListTile(
                contentPadding:
                const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                leading: Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius:
                    BorderRadius.circular(12),
                    color: _RecordingTheme.cyan
                        .withOpacity(.12),
                  ),
                  child: Icon(
                    index == 0
                        ? Icons.today_outlined
                        : Icons.schedule_rounded,
                    color: _RecordingTheme.cyan,
                  ),
                ),

                title: Text(
                  options[index].label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                subtitle: const Text(
                  'Attempt camera playback',
                  style: TextStyle(
                    color: _RecordingTheme.muted,
                    fontSize: 12,
                  ),
                ),

                trailing: const Icon(
                  Icons.play_circle_outline,
                  color: _RecordingTheme.cyan,
                ),

                onTap: () {
                  _play(
                    context,
                    options[index],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Shared panel design.
BoxDecoration _panelDecoration() {
  return BoxDecoration(
    color: _RecordingTheme.surface,
    borderRadius: BorderRadius.circular(17),
    border: Border.all(
      color: _RecordingTheme.border,
    ),
  );
}

// Introduction card.
class _IntroCard extends StatelessWidget {
  const _IntroCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
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
        border: Border.all(
          color: const Color(0xFF25617B),
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 31,
            color: _RecordingTheme.cyan,
          ),

          const SizedBox(height: 14),

          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),

          const SizedBox(height: 9),

          Text(
            subtitle,
            style: const TextStyle(
              color: _RecordingTheme.muted,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// Numbered section heading.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(
      this.number,
      this.title,
      );

  final String number;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          number,
          style: const TextStyle(
            color: _RecordingTheme.cyan,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

// Empty, loading, and error states.
class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _panelDecoration(),
      child: Column(
        children: [
          Icon(
            icon,
            color: _RecordingTheme.muted,
            size: 34,
          ),

          const SizedBox(height: 12),

          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _RecordingTheme.muted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// Information / compatibility note.
class _InfoNote extends StatelessWidget {
  const _InfoNote(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _RecordingTheme.cyan
            .withOpacity(.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _RecordingTheme.cyan
              .withOpacity(.22),
        ),
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            color: _RecordingTheme.cyan,
            size: 19,
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: _RecordingTheme.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
