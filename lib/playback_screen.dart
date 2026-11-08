
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:path_provider/path_provider.dart';

class VideoPlaybackScreen extends StatefulWidget {
  final String playbackUrl;

  const VideoPlaybackScreen({
    super.key,
    required this.playbackUrl,
  });

  @override
  State<VideoPlaybackScreen> createState() =>
      _VideoPlaybackScreenState();
}

class _VideoPlaybackScreenState
    extends State<VideoPlaybackScreen> {
  // Futuristic CCTV theme
  static const Color background = Color(0xFF080D18);
  static const Color surface = Color(0xFF111C2D);
  static const Color border = Color(0xFF26364B);
  static const Color cyan = Color(0xFF50D5F5);
  static const Color muted = Color(0xFF94A8C2);
  static const Color green = Color(0xFF4ADE80);
  static const Color red = Color(0xFFEF4444);

  late final VlcPlayerController _vlcController;

  bool _isCapturing = false;
  bool _captureBusy = false;

  double? _dragPosition;

  String? _savedClipPath;

  @override
  void initState() {
    super.initState();

    _vlcController = VlcPlayerController.network(
      widget.playbackUrl,
      hwAcc: HwAcc.full,
      autoPlay: true,
      options: VlcPlayerOptions(),
    );
  }

  @override
  void dispose() {
    _vlcController.dispose();
    super.dispose();
  }

  // Display messages without exposing camera credentials.
  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: surface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Extract safe camera information.
  String get _cameraHost {
    final uri = Uri.tryParse(widget.playbackUrl);

    if (uri == null || uri.host.isEmpty) {
      return 'IP Camera';
    }

    return uri.hasPort
        ? '${uri.host}:${uri.port}'
        : uri.host;
  }

  String get _cameraChannel {
    final uri = Uri.tryParse(widget.playbackUrl);

    return uri?.queryParameters['channel'] ?? '1';
  }

  // Convert a Duration into HH:mm:ss or mm:ss.
  String _formatTime(Duration duration) {
    final totalSeconds =
    duration.inSeconds.clamp(0, 99999999);

    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');

    if (hours > 0) {
      final hh = hours.toString().padLeft(2, '0');
      return '$hh:$mm:$ss';
    }

    return '$mm:$ss';
  }

  // Play or pause the recording.
  Future<void> _togglePlayPause() async {
    final value = _vlcController.value;

    if (!value.isInitialized) {
      _showMessage('Please wait for the player to load.');
      return;
    }

    try {
      if (value.isPlaying) {
        await _vlcController.pause();
      } else {
        await _vlcController.play();
      }
    } catch (_) {
      _showMessage('Unable to change playback state.');
    }
  }

  // Jump forward or backward by 30 seconds.
  Future<void> _jump(int seconds) async {
    final value = _vlcController.value;

    final duration = value.duration.inSeconds;

    if (!value.isInitialized || duration <= 0) {
      _showMessage(
        'Seeking is unavailable for this recording.',
      );
      return;
    }

    final current = value.position.inSeconds;

    final target = (current + seconds)
        .clamp(0, duration)
        .toInt();

    try {
      await _vlcController.seekTo(
        Duration(seconds: target),
      );
    } catch (_) {
      _showMessage('Unable to seek in this recording.');
    }
  }

  // Seek to a selected position on the timeline.
  Future<void> _seekTo(double milliseconds) async {
    final value = _vlcController.value;

    if (!value.isInitialized ||
        value.duration.inMilliseconds <= 0) {
      return;
    }

    final maximum = value.duration.inMilliseconds;

    final target = milliseconds
        .clamp(0.0, maximum.toDouble())
        .toInt();

    try {
      await _vlcController.seekTo(
        Duration(milliseconds: target),
      );
    } catch (_) {
      _showMessage('Unable to seek to this position.');
    }
  }

  // Reconnect to the selected camera recording.
  Future<void> _reconnect() async {
    if (_isCapturing) {
      _showMessage('Stop clip capture before reconnecting.');
      return;
    }

    try {
      await _vlcController.setMediaFromNetwork(
        widget.playbackUrl,
        autoPlay: true,
      );

      _showMessage('Reconnecting to the camera...');
    } catch (_) {
      _showMessage(
        'Connection failed. Check the camera and network.',
      );
    }
  }

  // Capture part of the currently playing stream.
  //
  // This uses VLC recording. It does NOT download
  // the full camera archive through HTTP.
  Future<void> _toggleClipCapture() async {
    if (_captureBusy) return;

    setState(() {
      _captureBusy = true;
    });

    try {
      if (_isCapturing) {
        final stopped =
        await _vlcController.stopRecording();

        final path = _vlcController.value.recordPath;

        if (!mounted) return;

        setState(() {
          _isCapturing = false;
          _savedClipPath =
          path.isNotEmpty ? path : null;
        });

        if (stopped == true && path.isNotEmpty) {
          _showMessage('Clip capture completed.');
        } else {
          _showMessage(
            'Capture stopped, but a saved file '
                'could not be confirmed.',
          );
        }

        return;
      }

      final value = _vlcController.value;

      if (!value.isInitialized || !value.isPlaying) {
        _showMessage(
          'Start playing a recording before capturing.',
        );
        return;
      }

      final directory =
      await getApplicationDocumentsDirectory();

      final clipDirectory = Directory(
        '${directory.path}/CCTVClips',
      );

      if (!await clipDirectory.exists()) {
        await clipDirectory.create(recursive: true);
      }

      final started =
      await _vlcController.startRecording(
        clipDirectory.path,
      );

      if (!mounted) return;

      if (started == true) {
        setState(() {
          _isCapturing = true;
          _savedClipPath = null;
        });

        _showMessage(
          'Clip capture started. Tap Stop Capture '
              'to finish saving.',
        );
      } else {
        _showMessage(
          'VLC could not capture this stream.',
        );
      }
    } catch (_) {
      _showMessage(
        'Clip capture failed or is unsupported '
            'for this camera.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _captureBusy = false;
        });
      }
    }
  }

  // Shared card decoration.
  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: border),
    );
  }

  // Dashboard introduction.
  Widget _buildHeader() {
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
              Icon(
                Icons.video_settings_outlined,
                color: cyan,
                size: 25,
              ),
              SizedBox(width: 10),
              Text(
                'CCTV CONTROL CENTER',
                style: TextStyle(
                  color: cyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),

          SizedBox(height: 16),

          Text(
            'Video Playback',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),

          SizedBox(height: 8),

          Text(
            'Review recorded camera footage '
                'with professional playback controls.',
            style: TextStyle(
              color: muted,
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  // VLC video player with error overlay.
  Widget _buildVideoPlayer() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: _cardDecoration(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                color: Colors.black,
                child: VlcPlayer(
                  controller: _vlcController,
                  aspectRatio: 16 / 9,
                  placeholder: const Center(
                    child: CircularProgressIndicator(
                      color: cyan,
                    ),
                  ),
                ),
              ),

              ValueListenableBuilder<VlcPlayerValue>(
                valueListenable: _vlcController,
                builder: (context, value, child) {
                  if (!value.hasError) {
                    return const SizedBox.shrink();
                  }

                  return Container(
                    color: Colors.black87,
                    padding: const EdgeInsets.all(16),
                    child: const Column(
                      mainAxisAlignment:
                      MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: red,
                          size: 36,
                        ),

                        SizedBox(height: 12),

                        Text(
                          'Unable to play recording',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),

                        SizedBox(height: 8),

                        Text(
                          'Check camera connection, '
                              'credentials and playback support.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: muted,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Display player connection status.
  Widget _buildStatus(VlcPlayerValue value) {
    String status;
    Color statusColor;

    if (value.hasError) {
      status = 'PLAYBACK ERROR';
      statusColor = red;
    } else if (value.isBuffering) {
      status = 'BUFFERING';
      statusColor = Colors.orangeAccent;
    } else if (value.isPlaying) {
      status = 'PLAYING';
      statusColor = green;
    } else if (value.isInitialized) {
      status = 'PAUSED / READY';
      statusColor = muted;
    } else {
      status = 'CONNECTING';
      statusColor = cyan;
    }

    return Container(
      padding: const EdgeInsets.all(17),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Icon(
            value.hasError
                ? Icons.error_outline
                : Icons.circle,
            color: statusColor,
            size: value.hasError ? 20 : 12,
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  '$_cameraHost  •  Channel $_cameraChannel',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          IconButton(
            tooltip: 'Reconnect',
            onPressed:
            _isCapturing ? null : _reconnect,
            icon: const Icon(
              Icons.refresh_rounded,
              color: cyan,
            ),
          ),
        ],
      ),
    );
  }

  // Reusable video control button.
  Widget _controlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool primary = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: primary
            ? cyan
            : const Color(0xFF1C2A3D),
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onPressed,
          child: SizedBox(
            width: primary ? 65 : 54,
            height: primary ? 60 : 54,
            child: Icon(
              icon,
              size: primary ? 33 : 27,
              color: onPressed == null
                  ? muted
                  : primary
                  ? background
                  : Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  // Play, pause, rewind, forward and timeline.
  Widget _buildControls(VlcPlayerValue value) {
    final durationMs =
    value.duration.inMilliseconds.toDouble();

    final maximum =
    durationMs > 0 ? durationMs : 1.0;

    final current = value.position.inMilliseconds
        .toDouble()
        .clamp(0.0, maximum)
        .toDouble();

    final sliderValue = (_dragPosition ?? current)
        .clamp(0.0, maximum)
        .toDouble();

    final canSeek =
        value.isInitialized && durationMs > 0;

    final displayedPosition =
    _dragPosition == null
        ? value.position
        : Duration(
      milliseconds: sliderValue.toInt(),
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.tune_rounded,
                color: cyan,
                size: 23,
              ),
              SizedBox(width: 10),
              Text(
                'Playback Controls',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),

          const SizedBox(height: 25),

          Row(
            mainAxisAlignment:
            MainAxisAlignment.center,
            children: [
              _controlButton(
                icon: Icons.replay_30_rounded,
                tooltip: 'Rewind 30 seconds',
                onPressed: canSeek
                    ? () => _jump(-30)
                    : null,
              ),

              const SizedBox(width: 18),

              _controlButton(
                icon: value.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                tooltip: value.isPlaying
                    ? 'Pause'
                    : 'Play',
                primary: true,
                onPressed: value.isInitialized
                    ? _togglePlayPause
                    : null,
              ),

              const SizedBox(width: 18),

              _controlButton(
                icon: Icons.forward_30_rounded,
                tooltip: 'Forward 30 seconds',
                onPressed: canSeek
                    ? () => _jump(30)
                    : null,
              ),
            ],
          ),

          const SizedBox(height: 26),

          Row(
            mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatTime(displayedPosition),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),

              Text(
                durationMs > 0
                    ? _formatTime(value.duration)
                    : '--:--',
                style: const TextStyle(
                  color: muted,
                ),
              ),
            ],
          ),

          const SizedBox(height: 5),

          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: cyan,
              inactiveTrackColor:
              const Color(0xFF34455C),
              thumbColor: cyan,
              overlayColor: cyan.withOpacity(0.15),
              trackHeight: 4,
            ),
            child: Slider(
              min: 0,
              max: maximum,
              value: sliderValue,
              onChangeStart: canSeek
                  ? (position) {
                setState(() {
                  _dragPosition = position;
                });
              }
                  : null,
              onChanged: canSeek
                  ? (position) {
                setState(() {
                  _dragPosition = position;
                });
              }
                  : null,
              onChangeEnd: canSeek
                  ? (position) {
                setState(() {
                  _dragPosition = null;
                });

                _seekTo(position);
              }
                  : null,
            ),
          ),

          if (!canSeek)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Timeline controls become available '
                    'when the camera reports a valid duration.',
                style: TextStyle(
                  color: muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Save clips using VLC's native recording feature.
  Widget _buildClipCapture() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.video_file_outlined,
                color: cyan,
                size: 24,
              ),
              SizedBox(width: 10),
              Text(
                'Video Clip Capture',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          const Text(
            'Capture a portion of the video '
                'while it is playing. This does not '
                'download the entire camera recording.',
            style: TextStyle(
              color: muted,
              fontSize: 13,
              height: 1.6,
            ),
          ),

          const SizedBox(height: 18),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _captureBusy
                  ? null
                  : _toggleClipCapture,
              style: FilledButton.styleFrom(
                backgroundColor:
                _isCapturing ? red : cyan,
                foregroundColor:
                _isCapturing
                    ? Colors.white
                    : background,
                shape: RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(14),
                ),
              ),
              icon: Icon(
                _isCapturing
                    ? Icons.stop_circle_outlined
                    : Icons.fiber_manual_record,
              ),
              label: Text(
                _captureBusy
                    ? 'Please wait...'
                    : _isCapturing
                    ? 'Stop Capture'
                    : 'Start Clip Capture',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),

          if (_savedClipPath != null) ...[
            const SizedBox(height: 16),

            const Text(
              'Saved clip location:',
              style: TextStyle(
                color: cyan,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),

            const SizedBox(height: 6),

            SelectableText(
              _savedClipPath!,
              style: const TextStyle(
                color: muted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],

          const SizedBox(height: 14),

          const Text(
            'Captured clips are saved inside '
                'application storage. Some camera '
                'streams may not support recording.',
            style: TextStyle(
              color: muted,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isCapturing,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isCapturing) {
          _showMessage(
            'Stop clip capture before leaving.',
          );
        }
      },

      child: Scaffold(
        backgroundColor: background,

        appBar: AppBar(
          title: const Text(
            'Video Playback',
            style: TextStyle(
              fontWeight: FontWeight.w800,
            ),
          ),
          backgroundColor: background,
          foregroundColor: Colors.white,
          centerTitle: false,
        ),

        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              18,
              12,
              18,
              32,
            ),
            children: [
              _buildHeader(),

              const SizedBox(height: 22),

              _buildVideoPlayer(),

              const SizedBox(height: 16),

              // Camera and connection status.
              ValueListenableBuilder<VlcPlayerValue>(
                valueListenable: _vlcController,
                builder: (context, value, child) {
                  return _buildStatus(value);
                },
              ),

              const SizedBox(height: 16),

              // Timeline and playback buttons.
              ValueListenableBuilder<VlcPlayerValue>(
                valueListenable: _vlcController,
                builder: (context, value, child) {
                  return _buildControls(value);
                },
              ),

              const SizedBox(height: 16),

              // Optional clip capture.
              _buildClipCapture(),
            ],
          ),
        ),
      ),
    );
  }
}
