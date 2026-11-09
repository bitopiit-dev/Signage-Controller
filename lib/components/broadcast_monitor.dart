import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';
import '../core/constants.dart';
import '../models/playlist_item.dart';
import '../utils/media_utils.dart';
import '../widgets/vintage_cd_player.dart';

/// Centre "program monitor": shows what every screen is showing right now.
class CommandCenterMonitor extends StatelessWidget {
  final String? jumpToFilename;
  final VideoPlayerController? previewController;
  final bool isPaused;
  final int clientCount;
  final int syncedCount;
  final PlaylistItem? activeItem;
  final PlaylistItem? nextItem;
  final int positionMs;
  final int durationMs;
  final String mediaDir;
  final bool shuffle;
  final bool repeatOne;
  final bool emergencyActive;
  final String emergencyMessage;
  final String? emergencyMediaFilename;
  final int emergencyRemainingSeconds;
  final bool screenSharingActive;
  final String screenSharingTargetLabel;
  final VoidCallback? onStopScreenShare;
  final bool monitorMuted;
  final VoidCallback? onToggleMonitorMute;
  final ValueChanged<int>? onSeekTo;

  const CommandCenterMonitor({
    super.key,
    required this.jumpToFilename,
    required this.previewController,
    required this.isPaused,
    required this.clientCount,
    this.syncedCount = 0,
    this.activeItem,
    this.nextItem,
    this.positionMs = 0,
    this.durationMs = 0,
    this.mediaDir = '',
    this.shuffle = false,
    this.repeatOne = false,
    this.emergencyActive = false,
    this.emergencyMessage = '',
    this.emergencyMediaFilename,
    this.emergencyRemainingSeconds = 0,
    this.screenSharingActive = false,
    this.screenSharingTargetLabel = 'Entire Computer Screen',
    this.onStopScreenShare,
    this.monitorMuted = true,
    this.onToggleMonitorMute,
    this.onSeekTo,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasActiveMedia = jumpToFilename != null && jumpToFilename!.isNotEmpty;
    final bool isShowingVideo = previewController != null &&
        previewController!.value.isInitialized &&
        activeItem != null &&
        activeItem!.type != MediaType.audio;

    Widget surface;
    if (!hasActiveMedia) {
      surface = const _StandbyState(key: ValueKey('standby'));
    } else if (isShowingVideo) {
      surface = _VideoSurface(key: ValueKey('v_$jumpToFilename'), controller: previewController!);
    } else {
      surface = _StaticMediaSurface(
        key: ValueKey('s_$jumpToFilename'),
        item: activeItem,
        mediaDir: mediaDir,
        isPaused: isPaused,
      );
    }

    return Expanded(
      child: Container(
        color: AppColors.spaceBlue,
        child: Stack(
          children: [
            // High-End Minimalist Frame
            Positioned.fill(
              child: Container(
                margin: const EdgeInsets.all(AppSpacing.s4),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(AppRadius.large),
                  border: Border.all(
                    color: (emergencyActive ? AppColors.dangerRose : AppColors.accentCyan).withOpacity(0.3),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accentCyan.withOpacity(0.05),
                      blurRadius: 100,
                      spreadRadius: 20,
                    ),
                    if (hasActiveMedia && !isPaused)
                      BoxShadow(
                        color: AppColors.accentCyan.withOpacity(0.15),
                        blurRadius: 40,
                        spreadRadius: -5,
                      ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 600),
                      switchInCurve: Curves.easeInOutCubic,
                      child: surface,
                    ),
                    // Legibility gradients for overlays
                    if (hasActiveMedia)
                      const IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xAA000000), Colors.transparent, Colors.transparent, Color(0xCC000000)],
                              stops: [0, 0.25, 0.65, 1],
                            ),
                          ),
                        ),
                      ),
                    if (screenSharingActive)
                      _ScreenSharePreview(
                        targetLabel: screenSharingTargetLabel,
                        onStopSharing: onStopScreenShare,
                      ),
                    if (emergencyActive)
                      _EmergencyPreview(
                        message: emergencyMessage,
                        mediaFilename: emergencyMediaFilename,
                        mediaDir: mediaDir,
                        remainingSeconds: emergencyRemainingSeconds,
                      ),
                  ],
                ),
              ),
            ),

            // Metadata Overlay (Top Corner)
            if (hasActiveMedia)
              Positioned(
                top: AppSpacing.s4 + 20,
                left: AppSpacing.s4 + 20,
                right: 260,
                child: _MetadataOverlay(
                  filename: jumpToFilename!,
                  type: activeItem?.type ?? MediaType.video,
                  clientCount: clientCount,
                  syncedCount: syncedCount,
                  isPaused: isPaused,
                ),
              ),

            // Broadcast Health Panel (Right Side)
            Positioned(
              top: AppSpacing.s4 + 20,
              right: AppSpacing.s4 + 20,
              child: _HealthPanel(
                clientCount: clientCount,
                syncedCount: syncedCount,
                nextItem: hasActiveMedia ? nextItem : null,
                mode: repeatOne ? 'REPEAT ONE' : (shuffle ? 'SHUFFLE' : 'SEQUENTIAL'),
                monitorMuted: monitorMuted,
                showAudioToggle: previewController != null,
                onToggleMonitorMute: onToggleMonitorMute,
              ),
            ),

            // Active Timeline (Bottom)
            if (hasActiveMedia)
              Positioned(
                bottom: AppSpacing.s4 + 14,
                left: AppSpacing.s4 + 20,
                right: AppSpacing.s4 + 20,
                child: _WaveformTimeline(
                  positionMs: positionMs,
                  durationMs: durationMs,
                  onSeekTo: onSeekTo,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StandbyState extends StatefulWidget {
  const _StandbyState({super.key});

  @override
  State<_StandbyState> createState() => _StandbyStateState();
}

class _StandbyStateState extends State<_StandbyState> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 0.8 + (_controller.value * 0.2),
              colors: [
                AppColors.accentCyan.withOpacity(0.05 * _controller.value),
                Colors.transparent,
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Opacity(
                opacity: 0.2 + (_controller.value * 0.3),
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.accentCyan, width: 1),
                  ),
                  child: const Icon(Icons.radar, size: 48, color: AppColors.accentCyan),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'SYSTEM STANDBY',
                style: TextStyle(
                  color: AppColors.accentCyan.withOpacity(0.35),
                  letterSpacing: 8,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Press play or double-tap an item to go live',
                style: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MetadataOverlay extends StatelessWidget {
  final String filename;
  final MediaType type;
  final int clientCount;
  final int syncedCount;
  final bool isPaused;

  const _MetadataOverlay({
    required this.filename,
    required this.type,
    required this.clientCount,
    required this.syncedCount,
    required this.isPaused,
  });

  @override
  Widget build(BuildContext context) {
    final allSynced = clientCount > 0 && syncedCount == clientCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          filename.toUpperCase(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
            shadows: [Shadow(color: Colors.black, blurRadius: 8)],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _Badge(
              text: isPaused ? 'PAUSED' : 'ON AIR',
              color: isPaused ? AppColors.warningAmber : AppColors.successEmerald,
            ),
            _Badge(
              text: mediaTypeToString(type).toUpperCase(),
              color: AppColors.accentCyan,
            ),
            _Badge(
              text: clientCount == 0 ? 'NO SCREENS CONNECTED' : 'SYNCED $syncedCount/$clientCount DEVICES',
              color: clientCount == 0
                  ? Colors.white38
                  : (allSynced ? AppColors.successEmerald : AppColors.warningAmber),
              isOutline: true,
            ),
          ],
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  final bool isOutline;

  const _Badge({
    required this.text,
    required this.color,
    this.isOutline = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isOutline ? Colors.black26 : color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _HealthPanel extends StatelessWidget {
  final int clientCount;
  final int syncedCount;
  final PlaylistItem? nextItem;
  final String mode;
  final bool monitorMuted;
  final bool showAudioToggle;
  final VoidCallback? onToggleMonitorMute;

  const _HealthPanel({
    required this.clientCount,
    required this.syncedCount,
    required this.nextItem,
    required this.mode,
    required this.monitorMuted,
    required this.showAudioToggle,
    this.onToggleMonitorMute,
  });

  @override
  Widget build(BuildContext context) {
    String health;
    Color healthColor;
    if (clientCount == 0) {
      health = 'NO SCREENS';
      healthColor = Colors.white38;
    } else if (syncedCount == clientCount) {
      health = 'IN SYNC';
      healthColor = AppColors.successEmerald;
    } else if (syncedCount == 0) {
      health = 'SYNCING';
      healthColor = AppColors.warningAmber;
    } else {
      health = 'PARTIAL';
      healthColor = AppColors.warningAmber;
    }
    return Container(
      width: 200,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(AppRadius.standard),
        border: Border.all(color: AppColors.glassWhite),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _HealthItem(label: 'SCREENS IN SYNC', value: '$syncedCount / $clientCount'),
          const SizedBox(height: 10),
          _HealthItem(label: 'PLAY MODE', value: mode),
          if (nextItem != null) ...[
            const SizedBox(height: 10),
            _HealthItem(label: 'UP NEXT', value: nextItem!.filename),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showAudioToggle)
                InkWell(
                  onTap: onToggleMonitorMute,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(monitorMuted ? Icons.headset_off_rounded : Icons.headset_rounded,
                            size: 14, color: monitorMuted ? Colors.white38 : AppColors.accentCyan),
                        const SizedBox(width: 4),
                        Text(monitorMuted ? 'MONITOR MUTED' : 'MONITOR AUDIO',
                            style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                                color: monitorMuted ? Colors.white38 : AppColors.accentCyan)),
                      ],
                    ),
                  ),
                ),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: healthColor,
                  boxShadow: [
                    BoxShadow(color: healthColor.withOpacity(0.5), blurRadius: 4, spreadRadius: 2),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                health,
                style: TextStyle(color: healthColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HealthItem extends StatelessWidget {
  final String label;
  final String value;

  const _HealthItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 8, fontWeight: FontWeight.bold),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _WaveformTimeline extends StatelessWidget {
  final int positionMs;
  final int durationMs;
  final ValueChanged<int>? onSeekTo;

  const _WaveformTimeline({
    required this.positionMs,
    required this.durationMs,
    this.onSeekTo,
  });

  @override
  Widget build(BuildContext context) {
    final double progress = durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;
    return LayoutBuilder(builder: (context, c) {
      void seekAt(double dx) {
        if (onSeekTo == null || durationMs <= 0) return;
        final f = (dx / c.maxWidth).clamp(0.0, 1.0);
        onSeekTo!((f * durationMs).round());
      }

      return Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => seekAt(d.localPosition.dx),
            child: SizedBox(
              height: 30,
              width: double.infinity,
              child: CustomPaint(
                painter: _WaveformPainter(progress: progress, color: AppColors.accentCyan),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatSeconds(positionMs ~/ 1000),
                style: const TextStyle(
                  color: AppColors.accentCyan,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              Text(
                'TAP TIMELINE TO SEEK ALL SCREENS',
                style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 1),
              ),
              Text(
                formatSeconds(durationMs ~/ 1000),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      );
    });
  }
}

class _WaveformPainter extends CustomPainter {
  final double progress;
  final Color color;

  _WaveformPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    const int barCount = 60;
    final double spacing = size.width / barCount;

    for (int i = 0; i < barCount; i++) {
      final double x = i * spacing + (spacing / 2);
      final double normalizedProgress = i / barCount;
      final double heightFactor = 0.3 + (math.sin(i * 0.5) * 0.3) + (math.cos(i * 0.8) * 0.2);
      final double barHeight = size.height * heightFactor.abs().clamp(0.1, 1.0);

      paint.color = normalizedProgress <= progress ? color : color.withOpacity(0.15);

      canvas.drawLine(
        Offset(x, size.height / 2 - barHeight / 2),
        Offset(x, size.height / 2 + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _VideoSurface extends StatelessWidget {
  final VideoPlayerController controller;
  const _VideoSurface({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio,
        child: VideoPlayer(controller),
      ),
    );
  }
}

class _StaticMediaSurface extends StatelessWidget {
  final PlaylistItem? item;
  final String mediaDir;
  final bool isPaused;
  const _StaticMediaSurface({super.key, this.item, required this.mediaDir, required this.isPaused});

  @override
  Widget build(BuildContext context) {
    final it = item;
    if (it != null && it.type == MediaType.image && mediaDir.isNotEmpty) {
      return Image.file(
        File(p.join(mediaDir, it.filename)),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _iconSurface(Icons.broken_image_rounded, 'IMAGE UNAVAILABLE'),
      );
    }
    if (it != null && it.type == MediaType.audio) {
      return Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(colors: [AppColors.actionBlue.withOpacity(0.15), Colors.transparent]),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(60),
            child: VintageCDPlayer(isPlaying: !isPaused),
          ),
        ),
      );
    }
    if (it != null && it.type == MediaType.youtube) {
      final id = MediaUtils.youtubeId(it.url);
      return Stack(
        fit: StackFit.expand,
        children: [
          if (id != null)
            Image.network(
              'https://img.youtube.com/vi/$id/hqdefault.jpg',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          Center(
            child: InkWell(
              onTap: () {
                if (it.url != null) MediaUtils.openUrl(it.url!);
              },
              borderRadius: BorderRadius.circular(40),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFF0000).withOpacity(0.7), width: 2),
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Color(0xFFFF0000), size: 40),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            left: 20,
            right: 20,
            child: Center(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF0000),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  if (it.url != null) MediaUtils.openUrl(it.url!);
                },
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('OPEN YOUTUBE VIDEO'),
              ),
            ),
          ),
        ],
      );
    }
    if (it != null && (it.type == MediaType.pdf || it.type == MediaType.document) && mediaDir.isNotEmpty) {
      final filePath = p.join(mediaDir, it.filename);
      return _iconSurface(
        it.type == MediaType.pdf ? Icons.picture_as_pdf_rounded : Icons.description,
        it.type == MediaType.pdf ? 'PDF BROADCAST' : 'DOCUMENT BROADCAST',
        filename: it.filename,
        onOpen: () => MediaUtils.openFile(filePath),
      );
    }
    if (it != null && (it.type == MediaType.video || it.type == MediaType.movie)) {
      return Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [AppColors.actionBlue.withOpacity(0.12), Colors.transparent],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.actionBlue.withOpacity(0.15),
                  border: Border.all(color: AppColors.actionBlue.withOpacity(0.5), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: AppColors.actionBlue.withOpacity(0.2), blurRadius: 25, spreadRadius: 2),
                  ],
                ),
                child: const Icon(Icons.movie_filter_rounded, size: 48, color: AppColors.accentCyan),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  it.filename,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.8),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'MASTER VIDEO BROADCAST ON AIR',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.accentCyan, letterSpacing: 2.0),
              ),
            ],
          ),
        ),
      );
    }
    return _iconSurface(
      it?.type == MediaType.pdf ? Icons.picture_as_pdf_rounded : Icons.description,
      it?.type == MediaType.pdf ? 'PDF BROADCAST' : 'STATIC ASSET BROADCAST',
    );
  }

  Widget _iconSurface(IconData icon, String label, {VoidCallback? onOpen, String? filename}) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [AppColors.accentCyan.withOpacity(0.1), Colors.transparent],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ShaderMask(
              shaderCallback: (bounds) => AppColors.primaryGradient.createShader(bounds),
              child: Icon(icon, size: 80, color: Colors.white),
            ),
            const SizedBox(height: 24),
            Text(
              label,
              style: TextStyle(
                color: AppColors.accentCyan.withOpacity(0.5),
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
                fontSize: 10,
              ),
            ),
            if (onOpen != null && filename != null) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.actionBlue,
                  foregroundColor: Colors.white,
                ),
                onPressed: onOpen,
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: Text('OPEN FILE: $filename'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmergencyPreview extends StatelessWidget {
  final String message;
  final String? mediaFilename;
  final String mediaDir;
  final int remainingSeconds;

  const _EmergencyPreview({
    required this.message,
    this.mediaFilename,
    this.mediaDir = '',
    this.remainingSeconds = 0,
  });

  @override
  Widget build(BuildContext context) {
    File? imageFile;
    if (mediaFilename != null && mediaFilename!.isNotEmpty && mediaDir.isNotEmpty) {
      final f = File(p.join(mediaDir, mediaFilename));
      if (f.existsSync()) imageFile = f;
    }

    return Container(
      color: const Color(0xE6400010),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.campaign, color: AppColors.dangerRose, size: 28),
                const SizedBox(width: 8),
                const Text('EMERGENCY BROADCAST',
                    style: TextStyle(color: AppColors.dangerRose, fontWeight: FontWeight.w900, letterSpacing: 3, fontSize: 13)),
                if (remainingSeconds > 0) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.dangerRose.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.dangerRose.withOpacity(0.5)),
                    ),
                    child: Text(
                      'AUTO-ENDS IN ${formatSeconds(remainingSeconds)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'JetBrains Mono',
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            if (imageFile != null) ...[
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 340),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.large),
                    border: Border.all(color: AppColors.dangerRose.withOpacity(0.5), width: 1.5),
                    boxShadow: [
                      BoxShadow(color: AppColors.dangerRose.withOpacity(0.2), blurRadius: 20, spreadRadius: 2),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.file(
                    imageFile,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, size: 48, color: Colors.white38),
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (message.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(AppRadius.standard),
                  border: Border.all(color: AppColors.dangerRose.withOpacity(0.3)),
                ),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScreenSharePreview extends StatelessWidget {
  final String targetLabel;
  final VoidCallback? onStopSharing;

  const _ScreenSharePreview({
    required this.targetLabel,
    this.onStopSharing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceNavy.withOpacity(0.95),
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.successEmerald.withOpacity(0.12),
                border: Border.all(color: AppColors.successEmerald.withOpacity(0.5), width: 1.5),
                boxShadow: [
                  BoxShadow(color: AppColors.successEmerald.withOpacity(0.2), blurRadius: 25, spreadRadius: 2),
                ],
              ),
              child: const Icon(Icons.cast_connected_rounded, size: 54, color: AppColors.successEmerald),
            ),
            const SizedBox(height: 20),
            const Text(
              'LIVE SCREEN SHARING ACTIVE',
              style: TextStyle(
                color: AppColors.successEmerald,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 3.0,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.glassWhite),
              ),
              child: Text(
                'STREAMING: ${targetLabel.toUpperCase()}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Your selected screen / window is streaming live to all connected TVs.\nYou can minimize or move this controller window freely.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5)),
            ),
            if (onStopSharing != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.dangerRose,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: const Icon(Icons.stop_screen_share_rounded, size: 18),
                label: const Text('STOP SHARING', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                onPressed: onStopSharing,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
