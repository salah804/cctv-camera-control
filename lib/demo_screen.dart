
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show PointerDeviceKind;

class DemoCamera {
  final String name;
  final String location;
  final String asset;

  const DemoCamera({
    required this.name,
    required this.location,
    required this.asset,
  });
}

class DemoSegment {
  final String name;
  final int startHour;
  final int endHour;
  final double videoFraction;

  const DemoSegment({
    required this.name,
    required this.startHour,
    required this.endHour,
    required this.videoFraction,
  });
}

class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key});

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  static const bg = Color(0xFF080D18);
  static const surface = Color(0xFF111C2D);
  static const border = Color(0xFF26364B);
  static const cyan = Color(0xFF50D5F5);
  static const muted = Color(0xFF94A8C2);
  static const green = Color(0xFF4ADE80);

  static const cameras = <DemoCamera>[
    DemoCamera(
      name: 'Demo Camera 01',
      location: 'Parking Lot',
      asset: 'assets/videos/demo_camera1.mp4',
    ),
    DemoCamera(
      name: 'Demo Camera 02',
      location: 'Warehouse',
      asset: 'assets/videos/demo_camera2.mp4',
    ),
  ];

  // These are simulated recording periods.
  // Each period maps to one third of the sample MP4.
  static const segments = <DemoSegment>[
    DemoSegment(
      name: 'Morning',
      startHour: 6,
      endHour: 9,
      videoFraction: 0.0,
    ),
    DemoSegment(
      name: 'Afternoon',
      startHour: 12,
      endHour: 15,
      videoFraction: 1 / 3,
    ),
    DemoSegment(
      name: 'Evening',
      startHour: 18,
      endHour: 21,
      videoFraction: 2 / 3,
    ),
  ];

  VideoPlayerController? _controller;

  // Scroll controller for desktop and mobile.
  final ScrollController _pageScrollController =
  ScrollController();

  int _selectedCamera = 0;
  int _loadId = 0;

  bool _liveMode = true;
  bool _loading = true;
  bool _muted = true;

  String? _error;

  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadCamera();
  }

  void _onVideoChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadCamera() async {
    final requestId = ++_loadId;
    final oldController = _controller;

    if (oldController != null) {
      oldController.removeListener(_onVideoChanged);
    }

    setState(() {
      _controller = null;
      _loading = true;
      _error = null;
    });

    if (oldController != null) {
      await oldController.dispose();
    }

    if (!mounted || requestId != _loadId) return;

    final asset = cameras[_selectedCamera].asset;
    final player = VideoPlayerController.asset(asset);

    try {
      await player.initialize();
      await player.setLooping(_liveMode);
      await player.setVolume(_muted ? 0 : 1);

      if (!mounted || requestId != _loadId) {
        await player.dispose();
        return;
      }

      player.addListener(_onVideoChanged);

      setState(() {
        _controller = player;
        _loading = false;
      });

      await player.play();
    } catch (e) {
      player.removeListener(_onVideoChanged);
      await player.dispose();

      if (!mounted || requestId != _loadId) return;

      setState(() {
        if (identical(_controller, player)) {
          _controller = null;
        }

        _loading = false;
        _error = 'Could not load $asset\n$e';
      });
    }
  }

  @override
  void dispose() {
    _loadId++;

    final player = _controller;

    if (player != null) {
      player.removeListener(_onVideoChanged);
      player.dispose();
    }

    _pageScrollController.dispose();
    super.dispose();
  }

  bool get _ready =>
      _controller != null &&
          _controller!.value.isInitialized &&
          !_controller!.value.hasError;

  void _selectCamera(int index) {
    if (index == _selectedCamera) return;

    setState(() {
      _selectedCamera = index;
    });

    _loadCamera();
  }

  Future<void> _setMode(bool live) async {
    if (_liveMode == live) return;

    setState(() {
      _liveMode = live;
    });

    final player = _controller;

    if (player == null || !player.value.isInitialized) {
      return;
    }

    try {
      await player.setLooping(live);

      if (!live) {
        await player.seekTo(Duration.zero);
      }

      await player.play();
    } catch (e) {
      _showMessage('Unable to switch modes: $e');
    }
  }

  Future<void> _togglePlayback() async {
    if (!_ready) return;

    final player = _controller!;

    if (player.value.isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> _seekToMilliseconds(int milliseconds) async {
    if (!_ready || _liveMode) return;

    final duration = _controller!.value.duration.inMilliseconds;
    final target = milliseconds.clamp(0, duration).toInt();

    await _controller!.seekTo(
      Duration(milliseconds: target),
    );
  }

  Future<void> _seekRelative(int seconds) async {
    if (!_ready || _liveMode) return;

    final current =
        _controller!.value.position.inMilliseconds;

    await _seekToMilliseconds(current + seconds * 1000);
  }

  Future<void> _jumpToSegment(int index) async {
    if (!_ready || _liveMode) return;

    final duration =
        _controller!.value.duration.inMilliseconds;

    final target =
    (duration * segments[index].videoFraction).round();

    await _seekToMilliseconds(target);
    await _controller!.play();
  }

  Future<void> _toggleMute() async {
    setState(() {
      _muted = !_muted;
    });

    await _controller?.setVolume(_muted ? 0 : 1);
  }

  int get _activeSegment {
    if (!_ready) return 0;

    final duration =
        _controller!.value.duration.inMilliseconds;

    if (duration <= 0) return 0;

    final position =
        _controller!.value.position.inMilliseconds;

    final fraction = position / duration;

    if (fraction < 1 / 3) return 0;
    if (fraction < 2 / 3) return 1;

    return 2;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: cyan,
              onPrimary: bg,
              surface: surface,
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

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes =
    duration.inMinutes.toString().padLeft(2, '0');

    final seconds =
    (duration.inSeconds % 60).toString().padLeft(2, '0');

    return '$minutes:$seconds';
  }

  String _dateText(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '${date.year}-$month-$day';
  }

  String _hourText(int hour) {
    return '${hour.toString().padLeft(2, '0')}:00';
  }

  BoxDecoration _decoration() {
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: border),
    );
  }

  Widget _panel(Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _decoration(),
      child: child,
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: cyan, size: 21),
        const SizedBox(width: 9),
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF15364B),
            surface,
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF25617B),
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: cyan),
              SizedBox(width: 10),
              Text(
                'CAMERA CONTROL',
                style: TextStyle(
                  color: cyan,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          SizedBox(height: 17),
          Text(
            'CCTV Demo Mode',
            style: TextStyle(
              color: Colors.white,
              fontSize: 27,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 9),
          Text(
            'Explore camera monitoring and recorded '
                'video playback without a physical IP camera.',
            style: TextStyle(
              color: muted,
              height: 1.6,
            ),
          ),
          SizedBox(height: 15),
          Row(
            children: [
              Icon(
                Icons.offline_bolt_outlined,
                color: green,
                size: 16,
              ),
              SizedBox(width: 7),
              Text(
                'OFFLINE • SIMULATED CAMERA SYSTEM',
                style: TextStyle(
                  color: green,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _modeButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          overflow: TextOverflow.ellipsis,
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: selected ? bg : muted,
          backgroundColor: selected ? cyan : surface,
          side: BorderSide(
            color: selected ? cyan : border,
          ),
          padding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 8,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return Row(
      children: [
        _modeButton(
          label: 'Live Demo',
          icon: Icons.videocam_outlined,
          selected: _liveMode,
          onPressed: () => _setMode(true),
        ),
        const SizedBox(width: 10),
        _modeButton(
          label: 'Playback',
          icon: Icons.history,
          selected: !_liveMode,
          onPressed: () => _setMode(false),
        ),
      ],
    );
  }

  Widget _buildVideoPanel() {
    final player = _controller;

    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.videocam_rounded,
                color: cyan,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cameras[_selectedCamera].name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                _liveMode ? 'LIVE DEMO' : 'PLAYBACK',
                style: const TextStyle(
                  color: green,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(
                color: Colors.black,
                child: _loading
                    ? const Center(
                  child: CircularProgressIndicator(
                    color: cyan,
                  ),
                )
                    : _error != null
                    ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.redAccent,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                        TextButton(
                          onPressed: _loadCamera,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
                    : _ready && player != null
                    ? Center(
                  child: AspectRatio(
                    aspectRatio:
                    player.value.aspectRatio > 0
                        ? player.value.aspectRatio
                        : 16 / 9,
                    child: VideoPlayer(player),
                  ),
                )
                    : const Center(
                  child: Text(
                    'Preparing video...',
                    style: TextStyle(color: muted),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            cameras[_selectedCamera].location,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _liveMode
                ? 'Looping a local video to simulate live monitoring.'
                : 'Playing locally stored demonstration footage.',
            style: const TextStyle(
              color: muted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    final player = _controller;

    final duration =
    _ready ? player!.value.duration : Duration.zero;

    final position =
    _ready ? player!.value.position : Duration.zero;

    final maxPosition = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;

    final sliderValue = position.inMilliseconds
        .toDouble()
        .clamp(0.0, maxPosition)
        .toDouble();

    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            'Playback Controls',
            Icons.tune_rounded,
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Back 10 seconds',
                onPressed: _ready && !_liveMode
                    ? () => _seekRelative(-10)
                    : null,
                icon: const Icon(Icons.replay_10),
                color: cyan,
                iconSize: 30,
              ),
              const SizedBox(width: 14),
              IconButton.filled(
                tooltip: 'Play / Pause',
                onPressed: _ready ? _togglePlayback : null,
                style: IconButton.styleFrom(
                  backgroundColor: cyan,
                  foregroundColor: bg,
                ),
                icon: Icon(
                  _ready && player!.value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 34,
                ),
              ),
              const SizedBox(width: 14),
              IconButton(
                tooltip: 'Forward 10 seconds',
                onPressed: _ready && !_liveMode
                    ? () => _seekRelative(10)
                    : null,
                icon: const Icon(Icons.forward_10),
                color: cyan,
                iconSize: 30,
              ),
              IconButton(
                tooltip: _muted ? 'Unmute' : 'Mute',
                onPressed: _ready ? _toggleMute : null,
                icon: Icon(
                  _muted
                      ? Icons.volume_off_outlined
                      : Icons.volume_up_outlined,
                ),
                color: cyan,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(position),
                style: const TextStyle(color: Colors.white),
              ),
              Text(
                _formatDuration(duration),
                style: const TextStyle(color: muted),
              ),
            ],
          ),
          Slider(
            value: sliderValue,
            min: 0,
            max: maxPosition,
            activeColor: cyan,
            inactiveColor: border,
            onChanged: _ready && !_liveMode
                ? (value) => _seekToMilliseconds(value.round())
                : null,
          ),
          if (_liveMode)
            const Text(
              'Switch to Playback to use the timeline.',
              style: TextStyle(
                color: muted,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCameraList() {
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            'Available Demo Cameras',
            Icons.grid_view_rounded,
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < cameras.length; i++) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => _selectCamera(i),
              leading: CircleAvatar(
                backgroundColor: cyan.withOpacity(0.12),
                child: const Icon(
                  Icons.videocam_outlined,
                  color: cyan,
                ),
              ),
              title: Text(
                cameras[i].name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                cameras[i].location,
                style: const TextStyle(color: muted),
              ),
              trailing: Icon(
                _selectedCamera == i
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: cyan,
              ),
            ),
            if (i != cameras.length - 1)
              const Divider(color: border),
          ],
        ],
      ),
    );
  }

  Widget _buildTimelineRail() {
    final activeIndex = _activeSegment;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        return Column(
          children: [
            SizedBox(
              height: 32,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: border),
                      ),
                    ),
                  ),
                  for (int i = 0; i < segments.length; i++)
                    Positioned(
                      left: width * segments[i].startHour / 24,
                      width: width *
                          (segments[i].endHour -
                              segments[i].startHour) /
                          24,
                      top: 3,
                      bottom: 3,
                      child: Material(
                        color: i == activeIndex
                            ? cyan
                            : const Color(0xFF24536C),
                        borderRadius: BorderRadius.circular(5),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(5),
                          onTap: () => _jumpToSegment(i),
                          child: Center(
                            child: Icon(
                              Icons.play_arrow,
                              size: 15,
                              color: i == activeIndex
                                  ? bg
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '00:00',
                  style: TextStyle(color: muted, fontSize: 10),
                ),
                Text(
                  '06:00',
                  style: TextStyle(color: muted, fontSize: 10),
                ),
                Text(
                  '12:00',
                  style: TextStyle(color: muted, fontSize: 10),
                ),
                Text(
                  '18:00',
                  style: TextStyle(color: muted, fontSize: 10),
                ),
                Text(
                  '24:00',
                  style: TextStyle(color: muted, fontSize: 10),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildTimeline() {
    final activeIndex = _activeSegment;

    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            'Recording Timeline',
            Icons.access_time_rounded,
          ),
          const SizedBox(height: 16),
          const Text(
            'Selected Date',
            style: TextStyle(
              color: muted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 7),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text(_dateText(_selectedDate)),
            style: OutlinedButton.styleFrom(
              foregroundColor: cyan,
              side: const BorderSide(color: border),
            ),
          ),
          const SizedBox(height: 20),
          _buildTimelineRail(),
          const SizedBox(height: 11),
          const Row(
            children: [
              Icon(
                Icons.circle,
                color: cyan,
                size: 10,
              ),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Blue blocks represent simulated recordings.',
                  style: TextStyle(
                    color: muted,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 21),
          const Text(
            'Available Recording Segments',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < segments.length; i++) ...[
            InkWell(
              onTap: () => _jumpToSegment(i),
              borderRadius: BorderRadius.circular(13),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: i == activeIndex
                      ? cyan.withOpacity(0.12)
                      : bg,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: i == activeIndex ? cyan : border,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      i == activeIndex
                          ? Icons.play_circle_fill
                          : Icons.play_circle_outline,
                      color: cyan,
                      size: 27,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${segments[i].name} Recording',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_hourText(segments[i].startHour)}'
                                ' - '
                                '${_hourText(segments[i].endHour)}',
                            style: const TextStyle(
                              color: muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: cyan,
                    ),
                  ],
                ),
              ),
            ),
            if (i != segments.length - 1)
              const SizedBox(height: 9),
          ],
          const SizedBox(height: 19),
          const Text(
            'DEMO NOTICE: The dates and recording hours '
                'are simulated. Each timeline segment jumps '
                'to a different part of the same local MP4. '
                'There is no real recording archive.',
            style: TextStyle(
              color: muted,
              fontSize: 11,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // RESPONSIVE WEB + MOBILE DEMO LAYOUT
  // ==========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        title: const Text(
          'CCTV Demo',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: kIsWeb ? 560 : double.infinity,
            ),
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                scrollbars: false,
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                },
              ),
              child: Scrollbar(
                controller: _pageScrollController,
                thumbVisibility: kIsWeb,
                interactive: true,
                child: ListView(
                  controller: _pageScrollController,
                  padding: const EdgeInsets.fromLTRB(
                    16, 16, 16, 35,
                  ),
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 20),
                    _buildModeSelector(),
                    const SizedBox(height: 16),
                    _buildVideoPanel(),
                    const SizedBox(height: 16),
                    _buildControls(),
                    if (!_liveMode) ...[
                      const SizedBox(height: 16),
                      _buildTimeline(),
                    ],
                    const SizedBox(height: 16),
                    _buildCameraList(),
                    const SizedBox(height: 28),
                    const Center(
                      child: Text(
                        'OFFLINE CCTV DEMONSTRATION\n'
                            'NO REAL CAMERA CONNECTED',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: muted,
                          fontSize: 11,
                          letterSpacing: 0.7,
                          height: 1.7,
                        ),
                      ),
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
