import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'models/playlist_item.dart';
import 'models/device_status.dart';
import 'utils/media_utils.dart';
import 'utils/transcoder.dart';
import 'core/theme.dart';
import 'core/constants.dart';
import 'components/app_header.dart';
import 'components/command_center_dock.dart';
import 'components/enterprise_library.dart';
import 'components/broadcast_monitor.dart';
import 'components/device_command_wall.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep the screen (and therefore the media server) alive while the
  // controller is open - if Android sleeps, every TV loses its master.
  WakelockPlus.enable().catchError((_) {});
  runApp(const ControllerApp());
}

class ControllerApp extends StatelessWidget {
  const ControllerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Signage Controller',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.enterpriseDark,
      home: const ControllerScreen(),
    );
  }
}

class ControllerScreen extends StatefulWidget {
  const ControllerScreen({super.key});

  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

/// Shared wire-protocol constants. The player uses the same values.
class SignageProtocol {
  static const String appId = 'bglit-signage-controller';
  static const int protocolVersion = 2;
  static const int discoveryPort = 45454;
  static const String discoveryMessage = 'BGLIT_SIGNAGE_DISCOVER';
}

class _ControllerScreenState extends State<ControllerScreen>
    with WidgetsBindingObserver {
  static const List<int> _portsToTry = [8888, 9090, 5500, 7777, 8080];

  // ── Server ───────────────────────────────────────────────
  HttpServer? _server;
  RawDatagramSocket? _discoverySocket;
  int _activePort = 8888;
  String _localIp = '0.0.0.0';
  String _mediaDir = '';
  bool _serverRunning = false;
  final DateTime _serverStartedAt = DateTime.now();

  // ── Library ──────────────────────────────────────────────
  List<PlaylistItem> _playlist = [];
  int _playlistVersion = DateTime.now().millisecondsSinceEpoch;
  int? _selectedIndex;
  final Set<int> _selectedIndices = {};
  bool _busyImporting = false;

  // ── Video conversion (ffmpeg) ────────────────────────────
  FfmpegTools? _ffmpeg;
  TranscodeQueue? _transcoder;

  // ── Master playback state (the single source of truth) ───
  bool _isStopped = true;
  bool _isPaused = false;
  String? _currentFilename;
  String? _nextFilename;
  int _startedAtMs = 0;
  int _pausedAccumulatedMs = 0;
  int _pauseStartedAtMs = 0;
  int _jumpSeq = 0;
  int _seekSeq = 0;
  int _syncSeq = 0;
  double _volume = 1.0;
  bool _shuffle = false;
  bool _repeatOne = false;
  final Random _random = Random();

  // ── Emergency broadcast ──────────────────────────────────
  bool _emergencyActive = false;
  String _emergencyMessage = '';
  String? _emergencyMediaFilename;
  int _emergencySeq = 0;
  int _emergencyDurationSeconds = 0;
  int _emergencyStartedAtMs = 0;

  int get _emergencyRemainingSeconds {
    if (!_emergencyActive || _emergencyDurationSeconds <= 0) return 0;
    final elapsedSec = (_nowMs - _emergencyStartedAtMs) ~/ 1000;
    return max(0, _emergencyDurationSeconds - elapsedSec);
  }

  void _checkEmergencyTimer() {
    if (!_emergencyActive || _emergencyDurationSeconds <= 0) return;
    final elapsedSec = (_nowMs - _emergencyStartedAtMs) ~/ 1000;
    if (elapsedSec >= _emergencyDurationSeconds) {
      _stopEmergency(reason: 'Timer expired');
    }
  }

  void _stopEmergency({String? reason}) {
    if (!_emergencyActive) return;
    setState(() {
      _emergencyActive = false;
      _emergencyDurationSeconds = 0;
      _emergencyStartedAtMs = 0;
      _emergencyMediaFilename = null;
      _emergencySeq++;
    });
    final logText = reason != null ? 'Emergency broadcast ended ($reason)' : 'Emergency broadcast ended';
    _log(logText, AppColors.successEmerald);
    _toast(logText);
  }

  // ── Screen sharing ───────────────────────────────────────
  bool _screenSharingActive = false;
  String _screenSharingTargetLabel = 'Entire Computer Screen';
  Process? _screenSharingProcess;
  int _screenSharingSeq = 0;

  Future<List<String>> _getOpenWindows() async {
    if (!Platform.isWindows) return [];
    try {
      final res = await Process.run(
        'powershell',
        ['-Command', 'Get-Process | Where-Object {\$_.MainWindowTitle} | Select-Object -ExpandProperty MainWindowTitle'],
        stdoutEncoding: utf8,
      );
      if (res.exitCode == 0) {
        final lines = (res.stdout as String)
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && s != 'Windows Input Experience' && s != 'Program Manager' && s != 'signagecontroller')
            .toList();
        return lines.toSet().toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _ensureWindowVisible(String windowTitle) async {
    if (!Platform.isWindows || windowTitle.isEmpty || windowTitle.contains('Entire Computer Screen')) return;
    try {
      final safeTitle = windowTitle.replaceAll("'", "''");
      final script = '''
\$code = @"
using System;
using System.Runtime.InteropServices;
public class WinUtil {
    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
}
"@
Add-Type -TypeDefinition \$code -ErrorAction SilentlyContinue
\$p = Get-Process | Where-Object { \$_.MainWindowTitle -like '*$safeTitle*' } | Select-Object -First 1
if (\$p) { [WinUtil]::ShowWindowAsync(\$p.MainWindowHandle, 4) }
''';
      await Process.run('powershell', ['-Command', script]);
    } catch (_) {}
  }

  Future<void> _toggleScreenSharing() async {
    if (_screenSharingActive) {
      _stopScreenSharing();
      return;
    }
    if (_ffmpeg == null) {
      _toast('FFmpeg tools not found on system');
      return;
    }

    String selectedTarget = 'desktop'; // 'desktop' or 'title=...'
    String selectedTargetLabel = 'My Computer Screen (Entire Desktop)';
    List<String> windows = await _getOpenWindows();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            backgroundColor: AppColors.surfaceNavy,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.large),
              side: const BorderSide(color: AppColors.glassWhite),
            ),
            title: Row(
              children: [
                const _DialogTitle(
                  icon: Icons.screen_share_rounded,
                  text: 'SHARE MY SCREEN',
                  color: AppColors.accentCyan,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: AppColors.accentCyan, size: 20),
                  tooltip: 'Refresh open windows',
                  onPressed: () async {
                    final updated = await _getOpenWindows();
                    setLocal(() => windows = updated);
                  },
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              height: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Select whether to share your entire computer screen or a specific application window live on all TVs.',
                      style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6))),
                  const SizedBox(height: 16),
                  _label('SELECT DISPLAY SOURCE'),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: [
                        _SourceOptionTile(
                          icon: Icons.desktop_windows_rounded,
                          title: 'My Computer Screen (Entire Desktop)',
                          subtitle: 'Shares your entire primary PC display live in real time',
                          selected: selectedTarget == 'desktop',
                          onTap: () => setLocal(() {
                            selectedTarget = 'desktop';
                            selectedTargetLabel = 'Entire Computer Screen';
                          }),
                        ),
                        const SizedBox(height: 8),
                        if (windows.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('RUNNING APPLICATION WINDOWS',
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white38, letterSpacing: 1.2)),
                          ),
                          for (final winTitle in windows) ...[
                            _SourceOptionTile(
                              icon: Icons.window_rounded,
                              title: winTitle,
                              subtitle: 'Share this specific application window',
                              selected: selectedTarget == 'title=$winTitle',
                              onTap: () => setLocal(() {
                                selectedTarget = 'title=$winTitle';
                                selectedTargetLabel = winTitle;
                              }),
                            ),
                            const SizedBox(height: 6),
                          ],
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.actionBlue),
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.cast_connected_rounded, size: 18),
                label: const Text('START SHARING'),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true) return;

    await _ensureWindowVisible(selectedTargetLabel);

    try {
      final targetPath = p.join(_mediaDir, 'screen_frame.jpg');
      final args = <String>[
        '-hide_banner',
        '-nostdin',
        '-y',
        '-f', 'gdigrab',
        '-framerate', '10',
        '-i', selectedTarget,
        '-vf', "scale=w='min(1920,iw)':h='min(1080,ih)':force_original_aspect_ratio=decrease,format=yuv420p",
        '-q:v', '4',
        '-update', '1',
        targetPath,
      ];

      final proc = await Process.start(_ffmpeg!.ffmpeg, args);
      _screenSharingProcess = proc;
      
      setState(() {
        _currentFilename = 'screen_frame.jpg';
        _isStopped = false;
        _isPaused = false;
        _screenSharingActive = true;
        _screenSharingTargetLabel = selectedTargetLabel;
        _screenSharingSeq++;
        _jumpSeq++;
      });

      _log('Live screen sharing started: $selectedTargetLabel', AppColors.successEmerald);
      _toast('Live screen sharing started ($selectedTargetLabel)');
    } catch (e) {
      _log('Failed to start screen sharing: $e', AppColors.dangerRose);
      _toast('Screen sharing failed: $e');
    }
  }

  void _stopScreenSharing() {
    if (!_screenSharingActive) return;
    _screenSharingProcess?.kill();
    _screenSharingProcess = null;
    setState(() {
      _screenSharingActive = false;
      _screenSharingSeq++;
      if (_playlist.isNotEmpty) {
        _currentFilename = _playlist.first.filename;
      } else {
        _isStopped = true;
        _currentFilename = null;
      }
      _jumpSeq++;
    });
    _log('Live screen sharing stopped', AppColors.warningAmber);
    _toast('Screen sharing stopped');
  }

  // ── Local preview on the controller ──────────────────────
  VideoPlayerController? _previewController;
  String? _previewFilename;
  bool _monitorMuted = true;

  // ── Devices ──────────────────────────────────────────────
  final Map<String, DeviceStatus> _devices = {};
  final Map<String, Map<String, dynamic>> _deviceCommands = {};
  final Map<String, Uint8List> _screenshots = {};
  final Map<String, int> _reportedDurationsMs = {};
  final List<ActivityEntry> _activity = [];
  final Set<String> _knownOffline = {};
  String _deviceFilter = 'total';

  Uint8List? _lastScreenShareBytes;

  Timer? _tickTimer;
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initApp();
    _tickTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      _tickAutoplay();
      _tickDevices();
      _checkEmergencyTimer();
      if (_screenSharingActive) _screenSharingSeq++;
      setState(() {});
    });
  }

  Future<void> _initApp() async {
    await _setupMediaDir();
    await _setupTranscoder();
    await _detectIp();
    await _startServer();
    await _startDiscoveryResponder();
    // Check existing videos in the background and convert any that TVs
    // cannot play (also fixes their durations).
    unawaited(_checkExistingVideos());
    // Signage should come back on air by itself after a restart.
    if (_playlist.isNotEmpty) {
      _playFileAtIndex(0, reason: 'Auto-start');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _transcoder?.cancelAll();
    _screenSharingProcess?.kill();
    _server?.close(force: true);
    _discoverySocket?.close();
    _tickTimer?.cancel();
    _saveDebounce?.cancel();
    _previewController?.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  //  ACTIVITY LOG
  // ═══════════════════════════════════════════════════════════

  void _log(String text, [Color color = AppColors.actionBlue]) {
    _activity.insert(0, ActivityEntry(text, color));
    if (_activity.length > 60) _activity.removeLast();
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceNavy,
        width: 420,
        duration: const Duration(seconds: 2),
      ));
  }

  // ═══════════════════════════════════════════════════════════
  //  TIMING
  // ═══════════════════════════════════════════════════════════

  int get _nowMs => DateTime.now().millisecondsSinceEpoch;

  /// Master position of the current item, driven by wall-clock so it works
  /// identically on every platform (even where video_player is missing).
  int _currentPositionMs() {
    if (_isStopped || _currentFilename == null || _startedAtMs == 0) return 0;
    final now = _nowMs;
    var pausedMs = _pausedAccumulatedMs;
    if (_isPaused && _pauseStartedAtMs != 0) pausedMs += now - _pauseStartedAtMs;
    return max(0, now - _startedAtMs - pausedMs);
  }

  PlaylistItem? get _currentItem {
    if (_currentFilename == null) return null;
    for (final i in _playlist) {
      if (i.filename == _currentFilename) return i;
    }
    return null;
  }

  int get _currentIndex =>
      _playlist.indexWhere((i) => i.filename == _currentFilename);

  int _effectiveDurationMs(PlaylistItem item) {
    final pc = _previewController;
    if (pc != null &&
        pc.value.isInitialized &&
        _previewFilename == item.filename &&
        pc.value.duration.inMilliseconds > 0) {
      return pc.value.duration.inMilliseconds;
    }
    if (item.isTimeBased) {
      final reported = _reportedDurationsMs[item.filename];
      if (reported != null && reported > 0) return reported;
    }
    return max(1, item.durationSeconds) * 1000;
  }

  // ═══════════════════════════════════════════════════════════
  //  PLAYBACK ENGINE
  // ═══════════════════════════════════════════════════════════

  void _tickAutoplay() {
    if (_isStopped || _isPaused || _playlist.isEmpty) return;
    final item = _currentItem;
    if (item == null) {
      // Current file was deleted - move on.
      _playFileAtIndex(0, reason: 'Recovered');
      return;
    }
    final duration = _effectiveDurationMs(item);
    final pos = _currentPositionMs();

    // Keep the local preview aligned with master time.
    final pc = _previewController;
    if (pc != null && pc.value.isInitialized && _previewFilename == item.filename) {
      final drift = (pc.value.position.inMilliseconds - pos).abs();
      if (drift > 1500 && pos < pc.value.duration.inMilliseconds) {
        pc.seekTo(Duration(milliseconds: pos));
      }
    }

    if (pos >= duration) {
      _advance();
    }
  }

  void _advance() {
    if (_playlist.isEmpty) return;
    var idx = _nextFilename == null
        ? -1
        : _playlist.indexWhere((i) => i.filename == _nextFilename);
    if (idx == -1) idx = (_currentIndex + 1) % _playlist.length;
    _playFileAtIndex(idx);
  }

  String? _computeNextFilename() {
    if (_playlist.isEmpty) return null;
    final cur = _currentIndex;
    if (_repeatOne && cur != -1) return _playlist[cur].filename;
    if (_shuffle && _playlist.length > 1) {
      var n = _random.nextInt(_playlist.length);
      if (n == cur) n = (n + 1) % _playlist.length;
      return _playlist[n].filename;
    }
    return _playlist[(max(cur, -1) + 1) % _playlist.length].filename;
  }

  void _playFileAtIndex(int index, {String? reason}) {
    if (index < 0 || index >= _playlist.length) return;
    final item = _playlist[index];
    setState(() {
      _currentFilename = item.filename;
      _startedAtMs = _nowMs;
      _pausedAccumulatedMs = 0;
      _pauseStartedAtMs = 0;
      _isStopped = false;
      _isPaused = false;
      _jumpSeq++;
      _syncSeq++;
      _selectedIndex = index;
      _nextFilename = _computeNextFilename();
    });
    if (reason != null) _log('$reason: ${item.filename}', AppColors.accentCyan);
    _syncLocalPreview();
  }

  void _togglePlayPause() {
    if (_playlist.isEmpty) {
      _toast('Add media to the library first');
      return;
    }
    if (_isStopped || _currentItem == null) {
      _playFileAtIndex(_selectedIndex ?? 0, reason: 'Go live');
      return;
    }
    setState(() {
      _isPaused = !_isPaused;
      if (_isPaused) {
        _pauseStartedAtMs = _nowMs;
        _previewController?.pause();
      } else {
        if (_pauseStartedAtMs != 0) {
          _pausedAccumulatedMs += _nowMs - _pauseStartedAtMs;
        }
        _pauseStartedAtMs = 0;
        _previewController?.play();
      }
    });
    _log(_isPaused ? 'Playback paused on all screens' : 'Playback resumed',
        AppColors.warningAmber);
  }

  void _stopAll() {
    setState(() {
      _isStopped = true;
      _isPaused = false;
      _currentFilename = null;
      _nextFilename = null;
      _startedAtMs = 0;
    });
    _disposePreview();
    _log('All screens set to STANDBY', AppColors.dangerRose);
  }

  void _next() {
    if (_playlist.isEmpty) return;
    if (_shuffle && _nextFilename != null) {
      _advance();
    } else {
      final cur = _currentIndex == -1 ? (_selectedIndex ?? -1) : _currentIndex;
      _playFileAtIndex((cur + 1) % _playlist.length, reason: 'Next');
    }
  }

  void _prev() {
    if (_playlist.isEmpty) return;
    // Classic behaviour: restart if we are more than 5 s in.
    if (!_isStopped && _currentItem != null && _currentPositionMs() > 5000) {
      _seekTo(0);
      return;
    }
    final cur = _currentIndex == -1 ? (_selectedIndex ?? 0) : _currentIndex;
    _playFileAtIndex((cur - 1 + _playlist.length) % _playlist.length,
        reason: 'Previous');
  }

  void _seekBy(int seconds) {
    if (_isStopped || _currentItem == null) return;
    _seekTo(_currentPositionMs() + seconds * 1000);
  }

  void _seekTo(int targetMs) {
    final item = _currentItem;
    if (item == null) return;
    final duration = _effectiveDurationMs(item);
    final pos = targetMs.clamp(0, max(0, duration - 1000)).toInt();
    final now = _nowMs;
    setState(() {
      _pausedAccumulatedMs = 0;
      _pauseStartedAtMs = _isPaused ? now : 0;
      _startedAtMs = now - pos;
      _seekSeq++;
    });
    _previewController?.seekTo(Duration(milliseconds: pos));
  }

  void _forceSync() {
    final masterPos = _currentPositionMs();
    setState(() {
      _syncSeq++;
      _seekSeq++;
      _playlistVersion++;
      for (final id in _devices.keys) {
        final c = _commandsFor(id);
        c['seekToMs'] = masterPos;
        c['seekTo'] = masterPos;
        c['seekSeq'] = (_syncSeq * 1000) + (masterPos ~/ 500);
        c['syncSeq'] = _syncSeq;
      }
    });
    _saveLibrary();
    _log('Force sync sent to all screens (${formatSeconds(masterPos ~/ 1000)})', AppColors.successEmerald);
    _toast('Synced all screens to ${formatSeconds(masterPos ~/ 1000)}');
  }

  void _setVolume(double v) {
    setState(() => _volume = v.clamp(0.0, 1.0));
    _applyPreviewVolume();
    _scheduleSave();
  }

  void _applyPreviewVolume() {
    _previewController?.setVolume(_monitorMuted ? 0 : _volume);
  }

  void _toggleShuffle() {
    setState(() {
      _shuffle = !_shuffle;
      _nextFilename = _computeNextFilename();
    });
    _scheduleSave();
  }

  void _toggleRepeat() {
    setState(() {
      _repeatOne = !_repeatOne;
      _nextFilename = _computeNextFilename();
    });
    _scheduleSave();
  }

  // ═══════════════════════════════════════════════════════════
  //  LOCAL PREVIEW
  // ═══════════════════════════════════════════════════════════

  Future<void> _disposePreview() async {
    final old = _previewController;
    _previewController = null;
    _previewFilename = null;
    if (mounted) setState(() {});
    if (old != null) {
      unawaited(old.dispose().catchError((_) {}));
    }
  }

  Future<void> _syncLocalPreview() async {
    await _disposePreview();
    final item = _currentItem;
    if (item == null || _mediaDir.isEmpty) return;
    if (!(item.type == MediaType.video ||
        item.type == MediaType.movie ||
        item.type == MediaType.audio)) {
      return;
    }
    final file = File(p.join(_mediaDir, item.filename));
    if (!await file.exists()) return;
    final requested = item.filename;
    try {
      final c = VideoPlayerController.file(file);
      await c.initialize();
      // Another item may have started while we were initialising.
      if (_currentFilename != requested || !mounted) {
        await c.dispose();
        return;
      }
      await c.setLooping(false);
      await c.setVolume(_monitorMuted ? 0 : _volume);
      final pos = _currentPositionMs();
      if (pos > 500) await c.seekTo(Duration(milliseconds: pos));
      if (!_isPaused && !_isStopped) await c.play();
      _previewController = c;
      _previewFilename = requested;
      if (c.value.duration.inMilliseconds > 0) {
        _reportedDurationsMs[requested] = c.value.duration.inMilliseconds;
      }
      if (mounted) setState(() {});
    } catch (e) {
      // video_player is not available on every desktop platform; master
      // timing keeps working from the wall clock.
      debugPrint('Preview unavailable: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  LIBRARY
  // ═══════════════════════════════════════════════════════════

  File get _libraryFile => File(p.join(_mediaDir, 'playlist.json'));

  Future<void> _setupMediaDir() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(baseDir.path, 'signage_controller', 'media'));
    if (!await dir.exists()) await dir.create(recursive: true);
    setState(() => _mediaDir = dir.path);
    await _loadExistingMedia();
  }

  Future<void> _loadExistingMedia() async {
    final dir = Directory(_mediaDir);
    final saved = <PlaylistItem>[];
    if (await _libraryFile.exists()) {
      try {
        final content = await _libraryFile.readAsString();
        if (content.trim().isNotEmpty) {
          final data = jsonDecode(content) as Map<String, dynamic>;
          for (final i in (data['items'] as List? ?? [])) {
            saved.add(PlaylistItem.fromJson(Map<String, dynamic>.from(i as Map)));
          }
          final settings = data['settings'] as Map<String, dynamic>?;
          if (settings != null) {
            _volume = ((settings['volume'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 1.0);
            _shuffle = settings['shuffle'] == true;
            _repeatOne = settings['repeatOne'] == true;
          } else if (data['volume'] is num) {
            _volume = (data['volume'] as num).toDouble().clamp(0.0, 1.0);
          }
        }
      } catch (e) {
        debugPrint('Error loading library: $e');
      }
    }

    final filesOnDisk = <String, String>{};
    await for (final f in dir.list()) {
      if (f is File) {
        final name = p.basename(f.path);
        if (name.startsWith('.') && name.endsWith('.part')) {
          // Leftover from an interrupted conversion.
          try {
            await f.delete();
          } catch (_) {}
          continue;
        }
        if (name == 'playlist.json' || name.startsWith('.')) continue;
        filesOnDisk[name] = f.path;
      }
    }

    // Keep the saved order (and YouTube links), then append new files.
    final items = <PlaylistItem>[];
    final seen = <String>{};
    for (final s in saved) {
      if (seen.contains(s.filename)) continue;
      if (s.type == MediaType.youtube || filesOnDisk.containsKey(s.filename)) {
        items.add(s);
        seen.add(s.filename);
      }
    }
    for (final entry in filesOnDisk.entries) {
      if (seen.contains(entry.key)) continue;
      final type = MediaUtils.getMediaType(entry.key);
      final duration = await MediaUtils.detectDuration(entry.value, type);
      items.add(PlaylistItem(filename: entry.key, type: type, durationSeconds: duration));
      seen.add(entry.key);
    }
    setState(() {
      _playlist = items;
      _playlistVersion++;
    });
    await _saveLibrary();
  }

  void _playlistChanged() {
    setState(() {
      _playlistVersion++;
      _nextFilename = _computeNextFilename();
    });
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), _saveLibrary);
  }

  Future<void> _saveLibrary() async {
    if (_mediaDir.isEmpty) return;
    final data = {
      'version': _playlistVersion,
      'settings': {
        'volume': _volume,
        'shuffle': _shuffle,
        'repeatOne': _repeatOne,
      },
      'items': _playlist.map((i) => i.toJson()).toList(),
    };
    try {
      await _libraryFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('Save failed: $e');
    }
  }

  Future<void> _importFiles(List<String> filePaths) async {
    if (_busyImporting || filePaths.isEmpty) return;
    setState(() => _busyImporting = true);
    var added = 0;
    var queued = 0;
    try {
      for (final filePath in filePaths) {
        final name = p.basename(filePath);
        // Videos are converted (if needed) straight from where they are,
        // so even multi-GB movies are never copied twice.
        if (MediaUtils.getMediaType(name) == MediaType.video && _transcoder != null) {
          _queueConversion(filePath);
          queued++;
          continue;
        }
        final dest = p.join(_mediaDir, name);
        if (p.normalize(filePath) != p.normalize(dest)) {
          await File(filePath).copy(dest);
        }
        final type = MediaUtils.getMediaType(name);
        final duration = await MediaUtils.detectDuration(dest, type);
        final existing = _playlist.indexWhere((i) => i.filename == name);
        final item = PlaylistItem(filename: name, type: type, durationSeconds: duration);
        setState(() {
          if (existing != -1) {
            _playlist[existing] = item; // replaced file
          } else {
            _playlist.add(item);
          }
        });
        _reportedDurationsMs.remove(name);
        added++;
      }
    } catch (e) {
      _toast('Import failed: $e');
    } finally {
      setState(() => _busyImporting = false);
    }
    if (queued > 0) {
      _toast('$queued video(s) are being prepared for the TVs – progress is shown in the library');
    }
    if (added > 0) {
      _playlistChanged();
      _log('$added file(s) added to library', AppColors.successEmerald);
      if (_isStopped && _playlist.length == added) {
        _playFileAtIndex(0, reason: 'Go live');
      }
    }
  }

  Future<void> _pickFiles() async {
    if (_busyImporting) return;
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;
    final paths = result.files.map((f) => f.path).whereType<String>().toList();
    await _importFiles(paths);
  }

  Future<void> _addYoutubeLink() async {
    final urlController = TextEditingController();
    final nameController = TextEditingController();
    final minutesController = TextEditingController(text: '5');
    String? error;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.surfaceNavy,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.large),
            side: const BorderSide(color: AppColors.glassWhite),
          ),
          title: const _DialogTitle(icon: Icons.smart_display_rounded, text: 'ADD YOUTUBE LINK'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(nameController, 'Display name', Icons.label_rounded),
                const SizedBox(height: 12),
                _field(urlController, 'YouTube URL', Icons.link_rounded),
                const SizedBox(height: 12),
                _field(minutesController, 'Fallback duration (minutes)', Icons.timer_rounded,
                    number: true),
                const SizedBox(height: 8),
                Text(
                  'Screens report the real video length once it starts; the fallback is used until then.',
                  style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4)),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: AppColors.dangerRose, fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
            ElevatedButton(
              onPressed: () {
                final id = MediaUtils.youtubeId(urlController.text);
                if (id == null) {
                  setLocal(() => error = 'That does not look like a YouTube link.');
                  return;
                }
                var name = nameController.text.trim();
                if (name.isEmpty) name = 'YouTube $id';
                if (_playlist.any((i) => i.filename == name)) {
                  setLocal(() => error = 'An item with this name already exists.');
                  return;
                }
                final minutes = int.tryParse(minutesController.text.trim()) ?? 5;
                setState(() => _playlist.add(PlaylistItem(
                      filename: name,
                      type: MediaType.youtube,
                      url: 'https://www.youtube.com/watch?v=$id',
                      durationSeconds: max(1, minutes) * 60,
                    )));
                _playlistChanged();
                _log('YouTube link added: $name', AppColors.successEmerald);
                Navigator.pop(ctx);
              },
              child: const Text('ADD'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editItem(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    final item = _playlist[index];
    var duration = item.durationSeconds.toDouble();
    var volume = item.volume;
    var transition = item.transition;
    final reported = _reportedDurationsMs[item.filename];
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.surfaceNavy,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.large),
            side: const BorderSide(color: AppColors.glassWhite),
          ),
          title: const _DialogTitle(icon: Icons.tune_rounded, text: 'ITEM SETTINGS'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.filename,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 20),
                _label(item.isTimeBased
                    ? 'FALLBACK DURATION  ${formatSeconds(duration.round())}'
                    : 'ON-SCREEN TIME  ${formatSeconds(duration.round())}'),
                if (item.isTimeBased)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      reported != null
                          ? 'Real length reported by screens: ${formatSeconds(reported ~/ 1000)} (used automatically)'
                          : 'The real media length is used automatically once known.',
                      style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4)),
                    ),
                  ),
                Slider(
                  value: duration.clamp(3.0, 3600.0),
                  min: 3,
                  max: 3600,
                  divisions: 3597,
                  onChanged: (v) => setLocal(() => duration = v),
                ),
                Wrap(
                  spacing: 6,
                  children: [5, 10, 15, 30, 60, 120, 300].map((s) {
                    return ActionChip(
                      label: Text(s < 60 ? '${s}s' : '${s ~/ 60}m', style: const TextStyle(fontSize: 11)),
                      onPressed: () => setLocal(() => duration = s.toDouble()),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                _label('ITEM VOLUME  ${(volume * 100).round()}%'),
                Slider(value: volume, onChanged: (v) => setLocal(() => volume = v)),
                const SizedBox(height: 8),
                _label('TRANSITION'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: TransitionType.values.map((t) {
                    return ChoiceChip(
                      label: Text(transitionTypeToString(t), style: const TextStyle(fontSize: 11)),
                      selected: transition == t,
                      onSelected: (_) => setLocal(() => transition = t),
                    );
                  }).toList(),
                ),
                if ((item.type == MediaType.video || item.type == MediaType.movie) && _transcoder != null) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accentCyan,
                        side: BorderSide(color: AppColors.accentCyan.withOpacity(0.6)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.movie_filter_rounded, size: 16),
                      label: const Text('CONVERT FOR ALL TVs', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      onPressed: () {
                        final path = p.join(_mediaDir, item.filename);
                        if (File(path).existsSync()) {
                          _queueConversion(path, replaces: item.filename);
                          _toast('Video conversion started for ${item.filename}');
                          Navigator.pop(ctx);
                        } else {
                          _toast('File not found in media folder');
                        }
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
            ElevatedButton(
              onPressed: () {
                final i = _playlist.indexWhere((x) => x.filename == item.filename);
                if (i != -1) {
                  setState(() => _playlist[i] = item.copyWith(
                        durationSeconds: duration.round(),
                        volume: volume,
                        transition: transition,
                      ));
                  _playlistChanged();
                  _log('Updated settings: ${item.filename}');
                }
                Navigator.pop(ctx);
              },
              child: const Text('SAVE'),
            ),
          ],
        ),
      ),
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    final selectedName =
        _selectedIndex != null && _selectedIndex! < _playlist.length ? _playlist[_selectedIndex!].filename : null;
    final multi = _selectedIndices.map((i) => _playlist[i].filename).toSet();
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _playlist.removeAt(oldIndex);
      _playlist.insert(newIndex, item);
      _selectedIndex = selectedName == null ? null : _playlist.indexWhere((i) => i.filename == selectedName);
      _selectedIndices
        ..clear()
        ..addAll([
          for (var i = 0; i < _playlist.length; i++)
            if (multi.contains(_playlist[i].filename)) i
        ]);
    });
    _playlistChanged();
  }

  Future<void> _deleteSelected() async {
    if (_selectedIndices.isEmpty) return;
    final count = _selectedIndices.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceNavy,
        title: const _DialogTitle(icon: Icons.delete_sweep_rounded, text: 'DELETE MEDIA', color: AppColors.dangerRose),
        content: Text('Remove $count item(s) from the library and delete the files?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.dangerRose),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final names = _selectedIndices.map((i) => _playlist[i]).toList();
    final removeNames = names.map((e) => e.filename).toSet();
    final t = _transcoder;
    if (t != null) {
      for (final j in List<TranscodeJob>.from(t.jobs)) {
        if (j.isActive && j.replaces != null && removeNames.contains(j.replaces)) t.cancel(j);
      }
    }
    var removedCurrent = false;
    for (final item in names) {
      if (item.filename == _currentFilename) removedCurrent = true;
      if (item.type != MediaType.youtube) {
        await _deleteMediaFile(item.filename);
      }
      _reportedDurationsMs.remove(item.filename);
    }
    setState(() {
      final removeSet = names.map((e) => e.filename).toSet();
      _playlist.removeWhere((i) => removeSet.contains(i.filename));
      _selectedIndices.clear();
      _selectedIndex = null;
    });
    _playlistChanged();
    _log('$count item(s) deleted', AppColors.dangerRose);
    if (removedCurrent) {
      if (_playlist.isEmpty) {
        _stopAll();
      } else {
        _playFileAtIndex(0, reason: 'Now playing');
      }
    }
  }

  void _selectAll(bool all) {
    setState(() {
      _selectedIndices.clear();
      if (all) _selectedIndices.addAll(List.generate(_playlist.length, (i) => i));
    });
  }

  // ═══════════════════════════════════════════════════════════
  //  VIDEO CONVERSION
  // ═══════════════════════════════════════════════════════════

  Future<void> _setupTranscoder() async {
    if (_mediaDir.isEmpty) return;
    // Also look in Documents\signage_controller\ffmpeg
    final appData = p.dirname(_mediaDir);
    final tools = await FfmpegTools.locate(extraDirs: [p.join(appData, 'ffmpeg')]);
    if (tools == null) {
      _log('ffmpeg not found – videos are added without conversion', AppColors.warningAmber);
      return;
    }
    _ffmpeg = tools;
    _transcoder = TranscodeQueue(
      tools: tools,
      mediaDir: _mediaDir,
      onUpdate: (_) {
        if (mounted) setState(() {});
      },
      onDone: _onConversionDone,
      onFailed: (job) {
        _log('Conversion failed: ${job.displayName}', AppColors.dangerRose);
        if (mounted) setState(() {});
      },
    );
    _log('Video converter ready (ffmpeg)', AppColors.successEmerald);
  }

  String _uniqueTargetName(String sourceName) {
    final base = p.basenameWithoutExtension(sourceName);
    bool taken(String n) =>
        _playlist.any((i) => i.filename == n) ||
        File(p.join(_mediaDir, n)).existsSync() ||
        (_transcoder?.isTargetTaken(n) ?? false);
    var name = '$base.mp4';
    var n = 2;
    while (taken(name)) {
      name = '$base ($n).mp4';
      n++;
    }
    return name;
  }

  void _queueConversion(String sourcePath, {String? replaces}) {
    final t = _transcoder;
    if (t == null) return;
    t.add(sourcePath, _uniqueTargetName(p.basename(sourcePath)), replaces: replaces);
    _log('Preparing for TVs: ${p.basename(sourcePath)}', AppColors.accentCyan);
  }

  void _onConversionDone(TranscodeJob job, String outputPath) {
    if (!mounted) return;
    final item = PlaylistItem(
      filename: job.targetName,
      type: MediaType.video,
      durationSeconds: max(1, job.outputDurationSec.round()),
    );
    var wasCurrent = false;
    setState(() {
      _reportedDurationsMs.remove(job.targetName);
      final idx = job.replaces == null ? -1 : _playlist.indexWhere((i) => i.filename == job.replaces);
      if (idx != -1) {
        final old = _playlist[idx];
        wasCurrent = !_isStopped && old.filename == _currentFilename;
        _playlist[idx] = item.copyWith(volume: old.volume, transition: old.transition);
        _reportedDurationsMs.remove(old.filename);
      } else {
        final existing = _playlist.indexWhere((i) => i.filename == job.targetName);
        if (existing != -1) {
          _playlist[existing] = item;
        } else {
          _playlist.add(item);
        }
      }
    });
    if (job.replaces != null && job.replaces != job.targetName) {
      _deleteMediaFile(job.replaces!);
    }
    _playlistChanged();
    _log('Ready for TVs: ${job.targetName}', AppColors.successEmerald);
    if (wasCurrent) {
      _playFileAtIndex(_playlist.indexWhere((i) => i.filename == job.targetName), reason: 'Now playing');
    } else if (_isStopped && _playlist.length == 1) {
      _playFileAtIndex(0, reason: 'Go live');
    }
  }

  /// Deletes a media file. Windows refuses while a TV is still streaming
  /// it, so keep retrying for a while.
  Future<void> _deleteMediaFile(String name, [int attempt = 0]) async {
    try {
      final f = File(p.join(_mediaDir, name));
      if (await f.exists()) await f.delete();
    } catch (e) {
      if (attempt < 20) {
        Timer(const Duration(seconds: 30), () => _deleteMediaFile(name, attempt + 1));
      } else {
        debugPrint('Delete failed: $e');
      }
    }
  }

  Future<void> _checkExistingVideos() async {
    final tools = _ffmpeg;
    final t = _transcoder;
    if (tools == null || t == null) return;
    final videos = _playlist.where((i) => i.type == MediaType.video || i.type == MediaType.movie).toList();
    var queued = 0;
    var changed = false;
    for (final item in videos) {
      if (t.jobs.any((j) => j.isActive && j.replaces == item.filename)) continue;
      final path = p.join(_mediaDir, item.filename);
      if (!await File(path).exists()) continue;
      final info = await probeMedia(tools, path);
      if (info == null) continue;
      if (!info.playableAsIs) {
        _log('Not TV-safe (${info.describe()}): ${item.filename}', AppColors.warningAmber);
        _queueConversion(path, replaces: item.filename);
        queued++;
      } else if (info.durationSec > 0) {
        // Exact length (Windows cannot read it through video_player).
        final secs = max(1, info.durationSec.round());
        final idx = _playlist.indexWhere((i) => i.filename == item.filename);
        if (idx != -1 && _playlist[idx].durationSeconds != secs) {
          _playlist[idx] = _playlist[idx].copyWith(durationSeconds: secs);
          changed = true;
        }
      }
    }
    if (changed && mounted) _playlistChanged();
    if (queued > 0) _log('$queued existing video(s) are being converted for TVs', AppColors.warningAmber);
  }

  Widget? _buildJobsPanel() {
    final t = _transcoder;
    if (t == null || t.jobs.isEmpty) return null;
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.s2, 6, AppSpacing.s2, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(AppRadius.standard),
        border: Border.all(color: AppColors.glassWhite),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.movie_filter_rounded, size: 16, color: AppColors.accentCyan),
            const SizedBox(width: 8),
            Expanded(child: _label('PREPARING VIDEOS FOR TVs (${t.activeJobs.length})')),
            if (t.jobs.any((j) => !j.isActive))
              TextButton(
                onPressed: () => setState(t.clearFinished),
                child: const Text('CLEAR', style: TextStyle(fontSize: 10)),
              ),
          ]),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [for (final j in t.jobs) _jobRow(j)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _jobRow(TranscodeJob j) {
    var status = '';
    var color = Colors.white54;
    switch (j.status) {
      case JobStatus.queued:
        status = 'Waiting…';
        break;
      case JobStatus.analyzing:
        status = 'Checking file…';
        break;
      case JobStatus.converting:
        final eta = j.eta;
        status = '${j.mode} ${(j.progress * 100).floor()}%${eta == null ? '' : ' · ~${_fmtEta(eta)} left'}';
        color = AppColors.accentCyan;
        break;
      case JobStatus.finalizing:
        status = 'Finishing…';
        color = AppColors.accentCyan;
        break;
      case JobStatus.done:
        status = 'Ready';
        color = AppColors.successEmerald;
        break;
      case JobStatus.failed:
        status = j.error ?? 'Failed';
        color = AppColors.dangerRose;
        break;
      case JobStatus.cancelled:
        status = 'Cancelled';
        break;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(j.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            if (j.isActive)
              InkWell(
                onTap: () => _transcoder?.cancel(j),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close_rounded, size: 14, color: Colors.white38),
                ),
              ),
          ]),
          const SizedBox(height: 4),
          if (j.isActive)
            LinearProgressIndicator(
              value: j.status == JobStatus.converting && j.progress > 0 ? j.progress : null,
              minHeight: 3,
              color: AppColors.accentCyan,
              backgroundColor: Colors.white10,
            ),
          const SizedBox(height: 3),
          Text(status, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: color)),
        ],
      ),
    );
  }

  String _fmtEta(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m';
    return '${d.inSeconds}s';
  }

  // ═══════════════════════════════════════════════════════════
  //  DEVICES
  // ═══════════════════════════════════════════════════════════

  void _tickDevices() {
    final now = _nowMs;
    final toForget = <String>[];
    _devices.forEach((id, d) {
      final online = d.isOnline(now);
      if (!online && !_knownOffline.contains(id)) {
        _knownOffline.add(id);
        _log('Heartbeat lost: ${d.name} (${d.ip})', AppColors.dangerRose);
      } else if (online && _knownOffline.contains(id)) {
        _knownOffline.remove(id);
        _log('Back online: ${d.name}', AppColors.successEmerald);
      }
      // Forget screens that have been gone for 30 minutes.
      if (now - d.lastSeenMs > 30 * 60 * 1000) toForget.add(id);
    });
    for (final id in toForget) {
      _forgetDevice(id, silent: true);
    }
  }

  void _forgetDevice(String id, {bool silent = false}) {
    final name = _devices[id]?.name ?? id;
    _devices.remove(id);
    _deviceCommands.remove(id);
    _screenshots.remove(id);
    _knownOffline.remove(id);
    if (!silent) _log('Removed $name from the wall', Colors.white38);
    if (mounted) setState(() {});
  }

  Map<String, dynamic> _commandsFor(String id) =>
      _deviceCommands.putIfAbsent(id, () => {'volume': 1.0, 'muted': false});

  void _bumpDeviceSeq(String id, String command) {
    final c = _commandsFor(id);
    c['${command}Seq'] = ((c['${command}Seq'] as int?) ?? 0) + 1;
  }

  void _deviceCommand(String id, String command, dynamic value) {
    final d = _devices[id];
    final label = d?.name ?? id;
    setState(() {
      final c = _commandsFor(id);
      switch (command) {
        case 'volume':
          c['volume'] = (value as num).toDouble().clamp(0.0, 1.0);
          break;
        case 'mute':
          c['muted'] = !(c['muted'] == true);
          _log('${c['muted'] == true ? 'Muted' : 'Unmuted'} $label', Colors.white54);
          break;
        case 'togglePause':
          final isP = c['paused'] == true;
          c['paused'] = !isP;
          c['syncMaster'] = false;
          _log('${c['paused'] == true ? 'Paused' : 'Resumed'} $label', AppColors.warningAmber);
          break;
        case 'playMedia':
          c['overrideFilename'] = value as String?;
          c['syncMaster'] = false;
          c['paused'] = false;
          c['stopped'] = false;
          _log('Assigned media to $label: $value', AppColors.accentCyan);
          break;
        case 'syncMaster':
          c['syncMaster'] = true;
          c['overrideFilename'] = null;
          c['paused'] = false;
          c['stopped'] = false;
          _log('Synced $label back to Master Loop', AppColors.successEmerald);
          break;
        case 'reboot':
          _bumpDeviceSeq(id, 'reboot');
          _log('Restart sent to $label', AppColors.dangerRose);
          break;
        case 'capture':
          _bumpDeviceSeq(id, 'capture');
          _log('Screenshot requested from $label', AppColors.actionBlue);
          break;
        case 'identify':
          _bumpDeviceSeq(id, 'identify');
          _log('Identify flashed on $label', AppColors.accentCyan);
          break;
        case 'clearCache':
          _bumpDeviceSeq(id, 'clearCache');
          break;
      }
    });
    if (command == 'reboot' || command == 'capture' || command == 'identify') {
      _toast('${command[0].toUpperCase()}${command.substring(1)} sent to $label');
    }
  }

  List<String> get _onlineIds {
    final now = _nowMs;
    return _devices.entries.where((e) => e.value.isOnline(now)).map((e) => e.key).toList();
  }

  void _rebootAll() {
    final ids = _onlineIds;
    if (ids.isEmpty) {
      _toast('No screens online');
      return;
    }
    setState(() {
      for (final id in ids) {
        _bumpDeviceSeq(id, 'reboot');
      }
    });
    _log('Restart sent to ${ids.length} screen(s)', AppColors.dangerRose);
    _toast('Restart sent to ${ids.length} screen(s)');
  }

  void _screenshotAll() {
    final ids = _onlineIds;
    if (ids.isEmpty) {
      _toast('No screens online');
      return;
    }
    setState(() {
      for (final id in ids) {
        _bumpDeviceSeq(id, 'capture');
      }
    });
    _log('Screenshot requested from ${ids.length} screen(s)');
    _toast('Capturing ${ids.length} screen(s)… thumbnails appear on the Command Wall');
  }

  void _clearCacheAll() {
    setState(() {
      for (final id in _devices.keys) {
        _bumpDeviceSeq(id, 'clearCache');
      }
    });
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    _log('Cache clear sent to ${_devices.length} screen(s)', AppColors.warningAmber);
    _toast('Cache cleared locally and on ${_devices.length} screen(s)');
  }

  Future<void> _toggleEmergency() async {
    if (_emergencyActive) {
      _stopEmergency(reason: 'Manual');
      return;
    }
    int durationSec = 0; // 0 = Manual / Until Ended
    String? selectedMediaFilename = _emergencyMediaFilename;
    bool isDragging = false;

    final msgController = TextEditingController(
        text: _emergencyMessage.isEmpty ? 'Please follow staff instructions and proceed to the nearest exit.' : _emergencyMessage);

    Future<void> handleAttachFilePath(String path, String name, Function(void Function()) setLocalState) async {
      final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
      final targetFilename = 'emergency_$safeName';
      final dest = p.join(_mediaDir, targetFilename);
      await File(path).copy(dest);
      setLocalState(() => selectedMediaFilename = targetFilename);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            backgroundColor: AppColors.surfaceNavy,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.large),
              side: BorderSide(color: AppColors.dangerRose.withOpacity(0.4)),
            ),
            title: const _DialogTitle(icon: Icons.campaign, text: 'EMERGENCY BROADCAST', color: AppColors.dangerRose),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('This message takes over every connected screen and mutes playback until ended or timer expires.',
                        style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6))),
                    const SizedBox(height: 16),
                    _label('EMERGENCY MESSAGE (TEXT)'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: msgController,
                      maxLines: 2,
                      autofocus: true,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.standard)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _label('EMERGENCY POSTER / IMAGE / MEDIA FILE (OPTIONAL)'),
                    const SizedBox(height: 6),
                    if (selectedMediaFilename != null && selectedMediaFilename!.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(AppRadius.standard),
                          border: Border.all(color: AppColors.accentCyan.withOpacity(0.5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.image_rounded, color: AppColors.accentCyan, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                selectedMediaFilename!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, color: AppColors.dangerRose, size: 18),
                              onPressed: () => setLocal(() => selectedMediaFilename = null),
                              tooltip: 'Remove media file',
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      DropTarget(
                        onDragEntered: (_) => setLocal(() => isDragging = true),
                        onDragExited: (_) => setLocal(() => isDragging = false),
                        onDragDone: (details) async {
                          setLocal(() => isDragging = false);
                          if (details.files.isNotEmpty) {
                            final f = details.files.first;
                            await handleAttachFilePath(f.path, f.name, setLocal);
                          }
                        },
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(AppRadius.standard),
                          child: InkWell(
                            onTap: () async {
                              final result = await FilePicker.platform.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'gif', 'mp4', 'pdf'],
                              );
                              if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
                                await handleAttachFilePath(result.files.first.path!, result.files.first.name, setLocal);
                              }
                            },
                            borderRadius: BorderRadius.circular(AppRadius.standard),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                              decoration: BoxDecoration(
                                color: isDragging ? AppColors.accentCyan.withOpacity(0.15) : Colors.black26,
                                borderRadius: BorderRadius.circular(AppRadius.standard),
                                border: Border.all(
                                  color: isDragging ? AppColors.accentCyan : AppColors.accentCyan.withOpacity(0.4),
                                  width: isDragging ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isDragging ? Icons.file_download_rounded : Icons.cloud_upload_rounded,
                                    size: 24,
                                    color: isDragging ? AppColors.accentCyan : AppColors.accentCyan,
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isDragging ? 'DROP IMAGE / FILE HERE NOW' : 'DRAG & DROP EMERGENCY IMAGE / FILE HERE',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: isDragging ? AppColors.accentCyan : Colors.white,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'or click to browse from computer (.jpg, .png, .mp4, .pdf)',
                                          style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.5)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _label('BROADCAST TIMER / DURATION'),
                        const Spacer(),
                        Text(
                          durationSec == 0
                              ? 'UNTIL ENDED (MANUAL)'
                              : '${formatSeconds(durationSec)} (${durationSec < 60 ? "$durationSec sec" : "${durationSec ~/ 60} min"})',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.accentCyan,
                            fontFamily: 'JetBrains Mono',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        0,   // Manual
                        30,  // 30s
                        60,  // 1m
                        120, // 2m
                        300, // 5m
                        600, // 10m
                        900, // 15m
                        1800,// 30m
                      ].map((sec) {
                        final selected = durationSec == sec;
                        final label = sec == 0
                            ? 'Manual'
                            : (sec < 60 ? '${sec}s' : '${sec ~/ 60}m');
                        return ChoiceChip(
                          label: Text(label, style: const TextStyle(fontSize: 11)),
                          selected: selected,
                          selectedColor: AppColors.dangerRose.withOpacity(0.25),
                          backgroundColor: Colors.white.withOpacity(0.04),
                          labelStyle: TextStyle(
                            color: selected ? Colors.white : Colors.white70,
                            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                          ),
                          side: BorderSide(
                            color: selected ? AppColors.dangerRose : Colors.white10,
                          ),
                          onSelected: (_) => setLocal(() => durationSec = sec),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.dangerRose),
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.campaign, size: 18),
                label: const Text('BROADCAST NOW'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    setState(() {
      _emergencyMessage = msgController.text.trim().isEmpty ? 'EMERGENCY' : msgController.text.trim();
      _emergencyMediaFilename = selectedMediaFilename;
      _emergencyDurationSeconds = durationSec;
      _emergencyStartedAtMs = _nowMs;
      _emergencyActive = true;
      _emergencySeq++;
    });
    if (durationSec > 0) {
      _log('EMERGENCY broadcast live (${formatSeconds(durationSec)} timer)', AppColors.dangerRose);
      _toast('Emergency broadcast live (${formatSeconds(durationSec)} timer)');
    } else {
      _log('EMERGENCY broadcast live', AppColors.dangerRose);
      _toast('Emergency broadcast live');
    }
  }

  void _showScreenshot(String id) {
    final bytes = _screenshots[id];
    if (bytes == null) return;
    final d = _devices[id];
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surfaceNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.large)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _DialogTitle(icon: Icons.screenshot_monitor, text: (d?.name ?? id).toUpperCase()),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                ]),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.standard),
                  child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
                ),
                const SizedBox(height: 8),
                Text('Video surfaces may appear black on some TVs (hardware-decoded video cannot be captured).',
                    style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  NETWORK
  // ═══════════════════════════════════════════════════════════

  Future<void> _detectIp() async {
    try {
      final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      String? best;
      var bestScore = -1;
      for (final iface in interfaces) {
        final n = iface.name.toLowerCase();
        for (final addr in iface.addresses) {
          final a = addr.address;
          if (addr.isLoopback || a.startsWith('169.254.')) continue;
          var score = 1;
          if (a.startsWith('192.168.')) {
            score = 4;
          } else if (a.startsWith('10.')) {
            score = 3;
          } else if (RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(a)) {
            score = 3;
          }
          if (n.contains('wlan') || n.contains('wi-fi') || n.contains('wifi') ||
              n.startsWith('eth') || n.startsWith('en') || n.contains('ethernet')) {
            score += 1;
          }
          if (n.contains('vmnet') || n.contains('virtual') || n.contains('vbox') ||
              n.contains('docker') || n.contains('rmnet')) {
            score -= 2;
          }
          if (score > bestScore) {
            bestScore = score;
            best = a;
          }
        }
      }
      if (best != null && best != _localIp) {
        setState(() => _localIp = best!);
        _log('Controller address: $best:$_activePort', AppColors.accentCyan);
      }
    } catch (e) {
      debugPrint('IP detection failed: $e');
    }
  }

  Map<String, dynamic> _buildEmergencyJson() {
    final bool hasEmergencyMedia = _emergencyActive && _emergencyMediaFilename != null && _emergencyMediaFilename!.isNotEmpty;
    final fn = _emergencyActive ? _emergencyMediaFilename : null;
    final mediaUrl = (fn != null && fn.isNotEmpty)
        ? 'http://$_localIp:$_activePort/$fn'
        : null;
    return {
      'active': hasEmergencyMedia ? false : _emergencyActive, // Must be false when poster image is attached so TV doesn't draw its text-only Evacuation Overlay!
      'message': _emergencyMessage,
      'mediaFilename': fn,
      'filename': fn,
      'image': fn,
      'file': fn,
      'media': fn,
      'mediaUrl': mediaUrl,
      'imageUrl': mediaUrl,
      'url': mediaUrl,
      'seq': _emergencySeq,
      'durationSeconds': _emergencyDurationSeconds,
      'remainingSeconds': _emergencyRemainingSeconds,
    };
  }

  Map<String, dynamic> _buildStateJson() {
    final pos = _currentPositionMs();
    final item = _currentItem;
    
    // Override currentFilename and items when emergency media or screen share is active
    final bool hasEmergencyMedia = _emergencyActive && _emergencyMediaFilename != null && _emergencyMediaFilename!.isNotEmpty;
    final bool isScreenSharing = _screenSharingActive;
    final String? activeOverrideFilename = hasEmergencyMedia
        ? _emergencyMediaFilename
        : (isScreenSharing ? 'screen_frame.jpg' : null);
    final bool hasMediaOverride = activeOverrideFilename != null;
    
    final effectiveCurrentFilename = hasMediaOverride
        ? activeOverrideFilename
        : (_isStopped ? null : _currentFilename);
        
    final effectiveItems = hasMediaOverride
        ? [
            PlaylistItem(
              filename: activeOverrideFilename,
              type: MediaUtils.getMediaType(activeOverrideFilename),
              durationSeconds: _emergencyDurationSeconds > 0 ? _emergencyDurationSeconds : 3600,
            ).toJson()
          ]
        : _playlist.map((i) => i.toJson()).toList();

    final bool isLive = hasMediaOverride ? true : !_isStopped;
    final bool isStopped = hasMediaOverride ? false : _isStopped;
    final bool isPaused = hasMediaOverride ? false : _isPaused;

    return {
      'app': SignageProtocol.appId,
      'protocol': SignageProtocol.protocolVersion,
      'version': _playlistVersion + (_emergencyActive ? 10000 : 0) + (_screenSharingActive ? 20000 : 0),
      'serverTime': _nowMs,
      'live': isLive,
      'stopped': isStopped,
      'paused': isPaused,
      'isPaused': isPaused,
      'isStopped': isStopped,
      'volume': _volume,
      'currentFilename': effectiveCurrentFilename,
      'currentPosition': pos ~/ 1000,
      'currentPositionMs': pos,
      'currentDurationMs': hasMediaOverride ? 3600000 : (item == null ? 0 : _effectiveDurationMs(item)),
      'nextFilename': hasMediaOverride ? activeOverrideFilename : (_isStopped ? null : _nextFilename),
      'jumpToSeq': _jumpSeq + (_emergencyActive ? 1000 : 0) + (_screenSharingActive ? 2000 : 0),
      'jumpToFilename': effectiveCurrentFilename,
      'seekSeq': _seekSeq,
      'syncSeq': _syncSeq,
      'shuffle': _shuffle,
      'repeatOne': _repeatOne,
      'screenSharing': {
        'active': _screenSharingActive,
        'url': _screenSharingActive ? 'http://$_localIp:$_activePort/screen_frame.jpg' : null,
        'seq': _screenSharingSeq,
      },
      'emergency': _buildEmergencyJson(),
      'emergencyItem': hasEmergencyMedia
          ? PlaylistItem(
              filename: _emergencyMediaFilename!,
              type: MediaUtils.getMediaType(_emergencyMediaFilename!),
              durationSeconds: _emergencyDurationSeconds > 0 ? _emergencyDurationSeconds : 3600,
            ).toJson()
          : null,
      'items': effectiveItems,
    };
  }

  Future<Response> _handleStatus(Request req) async {
    final body = await req.readAsString();
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(body) as Map);
    } catch (_) {
      return Response(400, body: 'bad json');
    }
    final info = req.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    final ip = info?.remoteAddress.address ?? 'unknown';
    final id = (data['deviceId'] as String?)?.trim().isNotEmpty == true ? data['deviceId'] as String : ip;
    final now = _nowMs;

    if (mounted) {
      setState(() {
        final existing = _devices[id];
        if (existing == null) {
          final d = DeviceStatus(
            id: id,
            name: (data['deviceName'] as String?) ?? 'Screen ${ip.split('.').last}',
            ip: ip,
            firstSeenMs: now,
            lastSeenMs: now,
          )..updateFrom(data, ip, now);
          _devices[id] = d;
          _log('Screen connected: ${d.name} ($ip)', AppColors.successEmerald);
        } else {
          existing.updateFrom(data, ip, now);
        }
        // Screens know the real length of video/audio/YouTube items.
        // Only trust a report while the screen is actually playing the
        // current item, and never accept a length shorter than the position
        // already reached. Keep the longest value seen, so one bad report
        // (e.g. while a video is still loading) cannot cut playback short.
        final fn = data['filename'] as String?;
        final state = (data['state'] ??
                (data['isPaused'] == true ? 'paused' : 'playing'))
            .toString();
        final lastErr = (data['lastError'] ?? data['error'] ?? '').toString();
        final posMs = (data['positionMs'] as num?)?.toInt() ??
            (((data['position'] as num?)?.toInt() ?? 0) * 1000);
        final durMs = (data['durationMs'] as num?)?.toInt() ??
            (((data['duration'] as num?)?.toInt() ?? 0) * 1000);

        // Auto-detect TV hardware decoding errors and automatically convert the video for full compatibility
        if (fn != null && fn.isNotEmpty && (state == 'error' || lastErr.isNotEmpty)) {
          if (lastErr.contains('MediaCodec') ||
              lastErr.contains('cannot decode') ||
              lastErr.contains('VideoError') ||
              lastErr.contains('UNABLE TO PLAY') ||
              state == 'error') {
            final path = p.join(_mediaDir, fn);
            if (File(path).existsSync() && _transcoder != null) {
              if (!_transcoder!.jobs.any((j) => j.isActive && j.replaces == fn)) {
                _log('TV reported video decode error ($fn) – Auto-converting for TV compatibility', AppColors.warningAmber);
                _queueConversion(path, replaces: fn);
              }
            }
          }
        }

        if (fn != null &&
            fn == _currentFilename &&
            state == 'playing' &&
            durMs > 1000 &&
            durMs >= posMs) {
          final item = _playlist.where((i) => i.filename == fn).toList();
          if (item.isNotEmpty && item.first.isTimeBased) {
            final prev = _reportedDurationsMs[fn] ?? 0;
            _reportedDurationsMs[fn] = max(prev, durMs);
          }
        }
      });
    }
    final c = _commandsFor(id);
    final double devVol = ((c['volume'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 1.0);
    final bool devMuted = c['muted'] == true;
    final double effectiveVol = devMuted ? 0.0 : (devVol * _volume).clamp(0.0, 1.0);

    final bool devSync = c['syncMaster'] != false;
    final String? devOverride = c['overrideFilename'] as String?;
    final bool devPaused = c['paused'] == true;
    final bool devStopped = c['stopped'] == true;

    final commands = Map<String, dynamic>.from(c);
    final stateJson = _buildStateJson();

    final String? effectiveFn = devSync
        ? stateJson['currentFilename']
        : devOverride;

    final bool effectivePaused = devSync
        ? (stateJson['isPaused'] == true)
        : devPaused;

    final bool effectiveStopped = devSync
        ? (stateJson['isStopped'] == true)
        : devStopped;

    // Volume parameters sent to the TV screen
    commands['volume'] = effectiveVol;
    commands['deviceVolume'] = devVol;
    commands['masterVolume'] = _volume;
    commands['muted'] = devMuted;
    commands['isMuted'] = devMuted;

    // Send command boolean triggers alongside sequence counters for max compatibility across all TV player apps
    if ((commands['rebootSeq'] as int? ?? 0) > 0) {
      commands['reboot'] = true;
      commands['restart'] = true;
    }
    if ((commands['captureSeq'] as int? ?? 0) > 0) {
      commands['capture'] = true;
      commands['screenshot'] = true;
    }
    if ((commands['identifySeq'] as int? ?? 0) > 0) {
      commands['identify'] = true;
      commands['flash'] = true;
    }
    if ((commands['clearCacheSeq'] as int? ?? 0) > 0) {
      commands['clearCache'] = true;
    }

    // Merge playback state into commands map so poll-based TV apps get immediate updates
    commands['isPaused'] = effectivePaused;
    commands['paused'] = effectivePaused;
    commands['isStopped'] = effectiveStopped;
    commands['stopped'] = effectiveStopped;
    commands['live'] = !effectiveStopped;
    commands['syncMaster'] = devSync;

    final int masterPos = _currentPositionMs();
    final int devicePos = (data['positionMs'] as num?)?.toInt() ??
        (((data['position'] as num?)?.toInt() ?? 0) * 1000);
    final String? deviceFn = data['filename'] as String?;

    // High-frequency polling interval hint for TVs (300ms)
    commands['pollIntervalMs'] = 300;
    commands['targetPollIntervalMs'] = 300;

    // Ultra-Low Latency Auto Drift Correction (Sub-Second 400ms Threshold)
    if (devSync &&
        deviceFn != null &&
        deviceFn == _currentFilename &&
        _currentFilename != null &&
        !_isPaused &&
        !_isStopped &&
        !_screenSharingActive &&
        !_emergencyActive) {
      final int rawDriftMs = devicePos - masterPos; // positive = TV ahead, negative = TV behind
      final int absDriftMs = rawDriftMs.abs();

      if (absDriftMs > 400) {
        // Network travel time compensation (+25ms offset)
        final int targetPos = masterPos + 25;
        commands['seekToMs'] = targetPos;
        commands['seekTo'] = targetPos;
        commands['seekSeq'] = (_syncSeq * 10000) + (targetPos ~/ 200);
        commands['forceSync'] = true;
        
        // Speed nudge for smooth sub-second catches without audio pops
        if (absDriftMs < 1200) {
          commands['playbackSpeed'] = rawDriftMs < 0 ? 1.05 : 0.95;
        } else {
          commands['playbackSpeed'] = 1.0;
        }
      } else {
        commands['playbackSpeed'] = 1.0;
      }
    } else {
      commands['playbackSpeed'] = 1.0;
    }

    if (_screenSharingActive && devSync) {
      commands['screenShareUrl'] = 'http://$_localIp:$_activePort/screen_frame.jpg';
      commands['currentFilename'] = 'screen_frame.jpg';
      commands['jumpToFilename'] = 'screen_frame.jpg';
      commands['jumpTo'] = 'screen_frame.jpg';
    } else if (effectiveFn != null) {
      commands['currentFilename'] = effectiveFn;
      commands['jumpToFilename'] = effectiveFn;
      commands['jumpTo'] = effectiveFn;
    } else {
      commands['currentFilename'] = null;
      commands['jumpToFilename'] = null;
      commands['jumpTo'] = null;
    }
    commands['jumpToSeq'] = _jumpSeq;
    commands['seekSeq'] = _seekSeq;
    commands['syncSeq'] = _syncSeq;
    commands['playlistVersion'] = _playlistVersion;

    return Response.ok(
      jsonEncode({
        'ok': true,
        'commands': commands,
        'state': stateJson,
        'serverTime': now,
        'emergency': _buildEmergencyJson(),
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _handleScreenshot(Request req) async {
    final id = req.url.queryParameters['deviceId'] ?? 'unknown';
    final bytes = <int>[];
    await for (final chunk in req.read()) {
      bytes.addAll(chunk);
      if (bytes.length > 15 * 1024 * 1024) return Response(413);
    }
    if (mounted) {
      setState(() => _screenshots[id] = Uint8List.fromList(bytes));
      _log('Screenshot received from ${_devices[id]?.name ?? id}', AppColors.successEmerald);
    }
    return Response.ok('{"ok":true}', headers: {'Content-Type': 'application/json'});
  }

  String _getContentType(String filename) {
    final ext = p.extension(filename).toLowerCase();
    switch (ext) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.pdf':
        return 'application/pdf';
      case '.json':
        return 'application/json';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _startServer() async {
    if (_mediaDir.isEmpty) return;
    final dir = Directory(_mediaDir);
    if (!await dir.exists()) {
      debugPrint('Error: Media directory does not exist at $_mediaDir');
      return;
    }
    final handler = const Pipeline().addMiddleware(_corsMiddleware()).addHandler((req) async {
      try {
        final rawPath = req.url.path;
        final decodedPath = Uri.decodeComponent(rawPath).replaceAll('\\', '/');
        final cleanPath = decodedPath.startsWith('/') ? decodedPath.substring(1) : decodedPath;

        if (cleanPath == 'ping') {
          return Response.ok(
            jsonEncode({'app': SignageProtocol.appId, 'protocol': SignageProtocol.protocolVersion, 'port': _activePort, 'ip': _localIp}),
            headers: {'Content-Type': 'application/json'},
          );
        }
        if (cleanPath == 'playlist.json' || cleanPath == 'state.json') {
          return Response.ok(jsonEncode(_buildStateJson()), headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Cache-Control': 'no-store',
          });
        }
        if (cleanPath == 'status' && req.method == 'POST') return _handleStatus(req);
        if (cleanPath == 'screenshot' && req.method == 'POST') return _handleScreenshot(req);

        // Directly serve any file in the media directory
        final targetFile = File(p.join(_mediaDir, cleanPath));
        if (cleanPath == 'screen_frame.jpg' || cleanPath.startsWith('screen_frame')) {
          try {
            if (await targetFile.exists()) {
              final bytes = await targetFile.readAsBytes();
              if (bytes.length > 100) _lastScreenShareBytes = bytes;
            }
          } catch (_) {}
          if (_lastScreenShareBytes != null && _lastScreenShareBytes!.length > 100) {
            return Response.ok(
              _lastScreenShareBytes!,
              headers: {
                'Content-Type': 'image/jpeg',
                'Content-Length': '${_lastScreenShareBytes!.length}',
                'Cache-Control': 'no-cache, no-store, must-revalidate',
                'Pragma': 'no-cache',
                'Expires': '0',
                'Access-Control-Allow-Origin': '*',
              },
            );
          } else {
            // Fallback 1x1 black JPEG byte array if file is being written for the first time
            final fallbackJpeg = Uint8List.fromList([
              0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
              0x01, 0x01, 0x00, 0x48, 0x00, 0x48, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
              0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
              0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
              0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
              0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
              0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
              0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
              0x00, 0x01, 0x01, 0x22, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00, 0x01,
              0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
              0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
              0x0A, 0x0B, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00,
              0x7F, 0x00, 0x32, 0x8A, 0x00, 0xFF, 0xD9
            ]);
            return Response.ok(
              fallbackJpeg,
              headers: {
                'Content-Type': 'image/jpeg',
                'Content-Length': '${fallbackJpeg.length}',
                'Cache-Control': 'no-cache, no-store, must-revalidate',
                'Access-Control-Allow-Origin': '*',
              },
            );
          }
        }

        if (await targetFile.exists()) {
          final length = await targetFile.length();
          final contentType = _getContentType(cleanPath);
          return Response.ok(
            targetFile.openRead(),
            headers: {
              'Content-Type': contentType,
              'Content-Length': '$length',
              'Access-Control-Allow-Origin': '*',
              'Cache-Control': 'public, max-age=3600',
            },
          );
        }

        return Response.notFound('File not found: $cleanPath');
      } catch (e) {
        debugPrint('Request error: $e');
        return Response.internalServerError(body: '$e');
      }
    });
    for (final port in _portsToTry) {
      try {
        _server = await serve(handler, InternetAddress.anyIPv4, port, shared: false);
        _server!.autoCompress = false;
        setState(() {
          _activePort = port;
          _serverRunning = true;
        });
        _log('Media server running on port $port', AppColors.successEmerald);
        return;
      } catch (_) {}
    }
    _log('Could not open any server port!', AppColors.dangerRose);
  }

  /// Answers UDP broadcasts from players so they can find us without
  /// anyone typing an IP address.
  Future<void> _startDiscoveryResponder() async {
    try {
      final socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4, SignageProtocol.discoveryPort,
          reuseAddress: true);
      socket.broadcastEnabled = true;
      _discoverySocket = socket;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = socket.receive();
        if (dg == null) return;
        final msg = utf8.decode(dg.data, allowMalformed: true);
        if (!msg.startsWith(SignageProtocol.discoveryMessage)) return;
        final reply = utf8.encode(jsonEncode({
          'app': SignageProtocol.appId,
          'ip': _localIp,
          'port': _activePort,
        }));
        socket.send(reply, dg.address, dg.port);
      });
    } catch (e) {
      debugPrint('Discovery responder unavailable: $e');
    }
  }

  Middleware _corsMiddleware() => (Handler innerHandler) => (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type',
          });
        }
        final response = await innerHandler(request);
        return response.change(headers: {'Access-Control-Allow-Origin': '*'});
      };

  // ═══════════════════════════════════════════════════════════
  //  UI HELPERS
  // ═══════════════════════════════════════════════════════════

  Widget _field(TextEditingController c, String label, IconData icon, {bool number = false}) {
    return TextField(
      controller: c,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18, color: AppColors.accentCyan),
        filled: true,
        fillColor: Colors.black26,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.standard),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: Colors.white54));

  String _uptime() {
    final d = DateTime.now().difference(_serverStartedAt);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  // ═══════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final now = _nowMs;
    final devices = _devices.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final online = devices.where((d) => d.isOnline(now)).toList();
    final masterPos = _currentPositionMs();
    final activeItem = _currentItem;
    final durationMs = activeItem == null ? 0 : _effectiveDurationMs(activeItem);
    final syncedCount = online.where((d) =>
        d.filename == _currentFilename && _currentFilename != null && (d.positionMs - masterPos).abs() < 4000).length;
    PlaylistItem? nextItem;
    if (_nextFilename != null) {
      for (final i in _playlist) {
        if (i.filename == _nextFilename) nextItem = i;
      }
    }

    return Scaffold(
      body: LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 1280;
        return Column(
          children: [
            ProCommandHeader(
              serverRunning: _serverRunning,
              localIp: _localIp,
              activePort: _activePort,
              totalDevices: devices.length,
              onlineCount: online.length,
              offlineCount: devices.length - online.length,
              serverLoad: _uptime(),
              emergencyActive: _emergencyActive,
              emergencyRemainingSeconds: _emergencyRemainingSeconds,
              screenSharingActive: _screenSharingActive,
              screenSharingTargetLabel: _screenSharingTargetLabel,
              onToggleScreenShare: _toggleScreenSharing,
              activeFilter: _deviceFilter,
              onEmergencyBroadcast: _toggleEmergency,
              onForceSync: _forceSync,
              onStopAll: _stopAll,
              onScreenshotAll: _screenshotAll,
              onRefreshIp: () async {
                await _detectIp();
                _toast('Controller address: http://$_localIp:$_activePort');
              },
              onClearCache: _clearCacheAll,
              onCardTap: (type) {
                if (type == 'load') return;
                setState(() => _deviceFilter = _deviceFilter == type ? 'total' : type);
              },
            ),
            Expanded(
              child: Row(
                children: [
                  EnterpriseLibrary(
                    width: compact ? 330 : 400,
                    playlist: _playlist,
                    currentFilename: _isStopped ? null : _currentFilename,
                    selectedIndex: _selectedIndex,
                    selectedIndices: _selectedIndices,
                    busy: _busyImporting,
                    mediaDir: _mediaDir,
                    onItemSelected: (i) => setState(() => _selectedIndex = i),
                    onItemDoubleTap: (i) => _playFileAtIndex(i, reason: 'Now playing'),
                    onItemReorder: _onReorder,
                    onToggleSelect: (i) => setState(() =>
                        _selectedIndices.contains(i) ? _selectedIndices.remove(i) : _selectedIndices.add(i)),
                    onSelectAll: _selectAll,
                    onDeleteSelected: _deleteSelected,
                    onAddMedia: _pickFiles,
                    onFilesDropped: _importFiles,
                    onAddYoutube: _addYoutubeLink,
                    onEditItem: _editItem,
                    jobsPanel: _buildJobsPanel(),
                  ),
                  CommandCenterMonitor(
                    jumpToFilename: _isStopped ? null : _currentFilename,
                    previewController: _previewFilename == _currentFilename ? _previewController : null,
                    isPaused: _isPaused,
                    clientCount: online.length,
                    syncedCount: syncedCount,
                    activeItem: activeItem,
                    nextItem: nextItem,
                    positionMs: masterPos,
                    durationMs: durationMs,
                    mediaDir: _mediaDir,
                    shuffle: _shuffle,
                    repeatOne: _repeatOne,
                    emergencyActive: _emergencyActive,
                    emergencyMessage: _emergencyMessage,
                    emergencyMediaFilename: _emergencyMediaFilename,
                    emergencyRemainingSeconds: _emergencyRemainingSeconds,
                    screenSharingActive: _screenSharingActive,
                    screenSharingTargetLabel: _screenSharingTargetLabel,
                    onStopScreenShare: _stopScreenSharing,
                    monitorMuted: _monitorMuted,
                    onToggleMonitorMute: () {
                      setState(() => _monitorMuted = !_monitorMuted);
                      _applyPreviewVolume();
                    },
                    onSeekTo: (ms) => _seekTo(ms),
                  ),
                  DeviceCommandWall(
                    width: compact ? 310 : 350,
                    devices: devices,
                    playlist: _playlist,
                    filter: _deviceFilter,
                    commands: _deviceCommands,
                    screenshots: _screenshots,
                    currentFilename: _isStopped ? null : _currentFilename,
                    masterPositionMs: masterPos,
                    activity: _activity,
                    onCommand: _deviceCommand,
                    onViewScreenshot: _showScreenshot,
                    onForget: (id) => _forgetDevice(id),
                    onClearFilter: () => setState(() => _deviceFilter = 'total'),
                  ),
                ],
              ),
            ),
            CommandCenterDock(
              isPaused: _isPaused || _isStopped,
              isStopped: _isStopped,
              shuffle: _shuffle,
              repeatOne: _repeatOne,
              volume: _volume,
              onPlayPause: _togglePlayPause,
              onStop: _stopAll,
              onNext: _next,
              onPrev: _prev,
              onSeekBack: () => _seekBy(-10),
              onSeekForward: () => _seekBy(10),
              onShuffleToggle: _toggleShuffle,
              onRepeatToggle: _toggleRepeat,
              onSync: _forceSync,
              onRebootAll: _rebootAll,
              onVolumeChanged: _setVolume,
            ),
          ],
        );
      }),
    );
  }
}

class _DialogTitle extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _DialogTitle({required this.icon, required this.text, this.color = AppColors.accentCyan});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(AppRadius.standard),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        ),
      ],
    );
  }
}

class _SourceOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _SourceOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.standard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.standard),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.actionBlue.withOpacity(0.18) : Colors.black26,
            borderRadius: BorderRadius.circular(AppRadius.standard),
            border: Border.all(
              color: selected ? AppColors.actionBlue : AppColors.glassWhite,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: selected ? AppColors.accentCyan : Colors.white70),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                        color: selected ? Colors.white : Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.4)),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.actionBlue),
            ],
          ),
        ),
      ),
    );
  }
}
