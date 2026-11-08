import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../models/device_status.dart';
import '../models/playlist_item.dart';
import '../utils/media_utils.dart';

class DeviceCommandWall extends StatelessWidget {
  final double width;
  final List<DeviceStatus> devices;
  final List<PlaylistItem> playlist;
  final String filter; // total | active | critical
  final Map<String, Map<String, dynamic>> commands;
  final Map<String, Uint8List> screenshots;
  final String? currentFilename;
  final int masterPositionMs;
  final List<ActivityEntry> activity;
  final Function(String id, String command, dynamic value) onCommand;
  final Function(String id)? onViewScreenshot;
  final Function(String id)? onForget;
  final VoidCallback? onClearFilter;

  const DeviceCommandWall({
    super.key,
    this.width = 350,
    required this.devices,
    this.playlist = const [],
    required this.onCommand,
    this.filter = 'total',
    this.commands = const {},
    this.screenshots = const {},
    this.currentFilename,
    this.masterPositionMs = 0,
    this.activity = const [],
    this.onViewScreenshot,
    this.onForget,
    this.onClearFilter,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final onlineCount = devices.where((d) => d.isOnline(now)).length;
    final visible = devices.where((d) {
      if (filter == 'active') return d.isOnline(now);
      if (filter == 'critical') return !d.isOnline(now);
      return true;
    }).toList()
      // Online first
      ..sort((a, b) => (b.isOnline(now) ? 1 : 0) - (a.isOnline(now) ? 1 : 0));

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          width: width,
          decoration: BoxDecoration(
            color: AppColors.surfaceNavy.withOpacity(0.7),
            border: const Border(
              left: BorderSide(color: AppColors.glassWhite, width: 1),
            ),
          ),
          child: Column(
            children: [
              _buildHeader(onlineCount),
              if (filter != 'total')
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.s2, 0, AppSpacing.s2, 8),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      onTap: onClearFilter,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.glassWhite),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.filter_alt_rounded, size: 12, color: AppColors.accentCyan),
                            const SizedBox(width: 6),
                            Text(
                              filter == 'active' ? 'SHOWING ACTIVE NODES' : 'SHOWING OFFLINE NODES',
                              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white54, letterSpacing: 1),
                            ),
                            const Spacer(),
                            const Icon(Icons.close_rounded, size: 12, color: Colors.white38),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: visible.isEmpty
                    ? _EmptyWall(filter: filter)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.s2, 0, AppSpacing.s2, AppSpacing.s2),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final d = visible[index];
                          return _DeviceControlCard(
                            key: ValueKey(d.id),
                            device: d,
                            nowMs: now,
                            playlist: playlist,
                            commands: commands[d.id] ?? const {},
                            screenshot: screenshots[d.id],
                            currentFilename: currentFilename,
                            masterPositionMs: masterPositionMs,
                            onCommand: onCommand,
                            onViewScreenshot: onViewScreenshot,
                            onForget: onForget,
                          );
                        },
                      ),
              ),
              _buildActivityFeed(now),
              _buildWatermark(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(int count) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s3),
      child: Row(
        children: [
          const Icon(Icons.router_rounded, color: AppColors.actionBlue, size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'COMMAND WALL',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.successEmerald.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.successEmerald.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(color: AppColors.successEmerald, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  '$count LIVE',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: AppColors.successEmerald,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityFeed(int now) {
    return Container(
      height: 140,
      padding: const EdgeInsets.all(AppSpacing.s2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        border: const Border(top: BorderSide(color: AppColors.glassWhite)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ACTIVITY FEED',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white38, letterSpacing: 1.5),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: activity.isEmpty
                ? Text('No activity yet', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.25)))
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: activity.length,
                    itemBuilder: (context, i) {
                      final a = activity[i];
                      return _ActivityItem(
                        text: a.text,
                        time: timeAgo(now - a.time.millisecondsSinceEpoch),
                        color: a.color,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildWatermark() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(AppSpacing.s2, 6, AppSpacing.s2, AppSpacing.s2),
      child: Tooltip(
        message: 'Open https://bitopiit-dev.github.io/#top',
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.large),
          child: InkWell(
            onTap: () => MediaUtils.openUrl('https://bitopiit-dev.github.io/#top'),
            borderRadius: BorderRadius.circular(AppRadius.large),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(AppRadius.large),
                border: Border.all(color: AppColors.accentCyan.withOpacity(0.3), width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Developed By K A Rahman',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withOpacity(0.7),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'BGL IT Signage',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.accentCyan,
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.open_in_new_rounded, size: 10, color: AppColors.accentCyan),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyWall extends StatelessWidget {
  final String filter;
  const _EmptyWall({required this.filter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tv_off_rounded, size: 40, color: Colors.white.withOpacity(0.15)),
            const SizedBox(height: 12),
            Text(
              filter == 'critical' ? 'NO OFFLINE SCREENS' : 'NO SCREENS CONNECTED',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.white38),
            ),
            const SizedBox(height: 6),
            Text(
              filter == 'critical'
                  ? 'Every screen is reporting in.'
                  : 'Open the Signage Player on a TV on the same Wi-Fi.\nIt finds this controller automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.3)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceControlCard extends StatelessWidget {
  final DeviceStatus device;
  final int nowMs;
  final List<PlaylistItem> playlist;
  final Map<String, dynamic> commands;
  final Uint8List? screenshot;
  final String? currentFilename;
  final int masterPositionMs;
  final Function(String, String, dynamic) onCommand;
  final Function(String id)? onViewScreenshot;
  final Function(String id)? onForget;

  const _DeviceControlCard({
    super.key,
    required this.device,
    required this.nowMs,
    this.playlist = const [],
    required this.commands,
    required this.screenshot,
    required this.currentFilename,
    required this.masterPositionMs,
    required this.onCommand,
    this.onViewScreenshot,
    this.onForget,
  });

  @override
  Widget build(BuildContext context) {
    final isOnline = device.isOnline(nowMs);
    final bool devSync = commands['syncMaster'] != false;
    final bool devPaused = commands['paused'] == true;
    final String? overrideFn = commands['overrideFilename'] as String?;

    final filename = (!devSync && overrideFn != null)
        ? overrideFn
        : (device.filename ?? (device.state == 'standby' ? 'Standby' : 'System Idle'));

    final progress = device.durationMs > 0 ? (device.positionMs / device.durationMs).clamp(0.0, 1.0) : 0.0;
    final muted = commands['muted'] == true;
    final volume = ((commands['volume'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 1.0);
    final inSync = devSync &&
        currentFilename != null &&
        device.filename == currentFilename &&
        ((device.positionMs - masterPositionMs).abs() < 4000 || currentFilename == 'screen_frame.jpg');
    final id = device.id;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: isOnline ? 1 : 0.55,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(AppRadius.large),
          border: Border.all(
            color: isOnline ? (devSync ? Colors.white.withOpacity(0.06) : AppColors.accentCyan.withOpacity(0.3)) : AppColors.dangerRose.withOpacity(0.25),
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _StatusBadge(isOnline: isOnline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          device.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: Colors.white),
                        ),
                      ),
                      Text(
                        isOnline ? 'Active ${timeAgo(nowMs - device.lastSeenMs)}' : 'Seen ${timeAgo(nowMs - device.lastSeenMs)}',
                        style: const TextStyle(fontSize: 9, color: Colors.white24),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${device.ip}${device.screen != null ? '  •  ${device.screen}' : ''}',
                    style: TextStyle(
                        fontFamily: 'JetBrains Mono', fontSize: 10, color: AppColors.accentCyan.withOpacity(0.7)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        devSync ? 'CURRENTLY PLAYING' : 'CUSTOM OVERRIDE MEDIA',
                        style: TextStyle(
                          fontSize: 8,
                          color: devSync ? Colors.white38 : AppColors.accentCyan,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const Spacer(),
                      if (isOnline)
                        _StateChip(
                          state: devPaused ? 'paused' : device.state,
                          inSync: inSync,
                          hasMaster: currentFilename != null,
                          isCustom: !devSync,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: !devSync ? AppColors.accentCyan : Colors.white.withOpacity(0.9),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (screenshot != null)
                        GestureDetector(
                          onTap: () => onViewScreenshot?.call(id),
                          child: Container(
                            margin: const EdgeInsets.only(left: 8),
                            width: 56,
                            height: 32,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.accentCyan.withOpacity(0.4)),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Image.memory(screenshot!, fit: BoxFit.cover, gaplessPlayback: true),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white.withOpacity(0.05),
                    valueColor: AlwaysStoppedAnimation(devSync ? (inSync ? AppColors.successEmerald : AppColors.actionBlue) : AppColors.accentCyan),
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${formatSeconds(device.positionMs ~/ 1000)} / ${formatSeconds(device.durationMs ~/ 1000)}',
                        style: const TextStyle(fontSize: 9, fontFamily: 'JetBrains Mono', color: Colors.white38),
                      ),
                      const Spacer(),
                      if (device.lastError != null && device.lastError!.isNotEmpty)
                        Flexible(
                          child: Text(
                            device.lastError!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 9, color: AppColors.dangerRose),
                          ),
                        ),
                    ],
                  ),
                  if (isOnline) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => onCommand(id, 'mute', null),
                          child: Icon(
                            muted || volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                            size: 16,
                            color: muted ? AppColors.dangerRose : Colors.white54,
                          ),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                              activeTrackColor: muted ? Colors.white24 : AppColors.actionBlue,
                              inactiveTrackColor: Colors.white10,
                              thumbColor: Colors.white,
                            ),
                            child: Slider(
                              value: volume,
                              onChanged: (v) => onCommand(id, 'volume', v),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 32,
                          child: Text(
                            muted ? 'MUTE' : '${(volume * 100).round()}%',
                            style: TextStyle(
                                fontSize: 9,
                                fontFamily: 'JetBrains Mono',
                                color: muted ? AppColors.dangerRose : Colors.white54),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.18),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppRadius.large)),
              ),
              child: isOnline
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        // Assign Media / Override
                        PopupMenuButton<String>(
                          tooltip: 'Assign specific media to this TV screen',
                          color: AppColors.surfaceNavy,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.standard),
                            side: const BorderSide(color: AppColors.glassWhite),
                          ),
                          onSelected: (val) {
                            if (val == '__SYNC_MASTER__') {
                              onCommand(id, 'syncMaster', null);
                            } else {
                              onCommand(id, 'playMedia', val);
                            }
                          },
                          itemBuilder: (ctx) => [
                            PopupMenuItem<String>(
                              value: '__SYNC_MASTER__',
                              child: Row(
                                children: [
                                  Icon(Icons.sync_rounded, size: 16, color: devSync ? AppColors.successEmerald : Colors.white70),
                                  const SizedBox(width: 8),
                                  Text(
                                    '🔄 Sync to Master Loop',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: devSync ? AppColors.successEmerald : Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(),
                            if (playlist.isEmpty)
                              const PopupMenuItem<String>(
                                enabled: false,
                                value: '',
                                child: Text('No media in library', style: TextStyle(fontSize: 11, color: Colors.white38)),
                              )
                            else
                              for (final item in playlist)
                                PopupMenuItem<String>(
                                  value: item.filename,
                                  child: Row(
                                    children: [
                                      Icon(
                                        item.type == MediaType.video || item.type == MediaType.movie
                                            ? Icons.play_circle_fill_rounded
                                            : Icons.image_rounded,
                                        size: 14,
                                        color: overrideFn == item.filename ? AppColors.accentCyan : Colors.white54,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          item.filename,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: overrideFn == item.filename ? FontWeight.bold : FontWeight.normal,
                                            color: overrideFn == item.filename ? AppColors.accentCyan : Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                          ],
                          child: Material(
                            color: Colors.transparent,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    devSync ? Icons.playlist_add_check_rounded : Icons.star_rounded,
                                    size: 15,
                                    color: devSync ? Colors.white70 : AppColors.accentCyan,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    devSync ? 'ASSIGN' : 'CUSTOM',
                                    style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w900,
                                      color: devSync ? Colors.white70 : AppColors.accentCyan,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Per-Device Pause / Resume
                        _ActionButton(
                          icon: devPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                          label: devPaused ? 'RESUME' : 'PAUSE',
                          color: devPaused ? AppColors.successEmerald : AppColors.warningAmber,
                          onPressed: () => onCommand(id, 'togglePause', null),
                        ),

                        // Restart TV
                        _ActionButton(
                          icon: Icons.power_settings_new_rounded,
                          label: 'RESTART',
                          color: AppColors.dangerRose,
                          onPressed: () => onCommand(id, 'reboot', true),
                        ),

                        // Capture Screenshot
                        _ActionButton(
                          icon: Icons.camera_alt_rounded,
                          label: 'CAPTURE',
                          color: AppColors.actionBlue,
                          onPressed: () => onCommand(id, 'capture', true),
                        ),

                        // Flash Identify Screen
                        _ActionButton(
                          icon: Icons.center_focus_strong_rounded,
                          label: 'IDENTIFY',
                          color: AppColors.accentCyan,
                          onPressed: () => onCommand(id, 'identify', true),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(left: 12),
                          child: Text('Waiting for heartbeat…', style: TextStyle(fontSize: 10, color: Colors.white38)),
                        ),
                        _ActionButton(
                          icon: Icons.delete_outline_rounded,
                          label: 'FORGET',
                          color: Colors.white54,
                          onPressed: () => onForget?.call(id),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  final String state;
  final bool inSync;
  final bool hasMaster;
  final bool isCustom;
  const _StateChip({
    required this.state,
    required this.inSync,
    required this.hasMaster,
    this.isCustom = false,
  });

  @override
  Widget build(BuildContext context) {
    String text;
    Color color;
    if (isCustom) {
      text = 'CUSTOM';
      color = AppColors.accentCyan;
    } else {
      switch (state) {
        case 'playing':
          text = hasMaster ? (inSync ? 'IN SYNC' : 'SYNCING') : 'PLAYING';
          color = inSync || !hasMaster ? AppColors.successEmerald : AppColors.warningAmber;
          break;
        case 'paused':
          text = 'PAUSED';
          color = AppColors.warningAmber;
          break;
        case 'buffering':
        case 'loading':
          text = 'BUFFERING';
          color = AppColors.warningAmber;
          break;
        case 'standby':
          text = 'STANDBY';
          color = Colors.white38;
          break;
        case 'error':
          text = 'ERROR';
          color = AppColors.dangerRose;
          break;
        case 'emergency':
          text = 'EMERGENCY';
          color = AppColors.dangerRose;
          break;
        default:
          text = state.toUpperCase();
          color = Colors.white38;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(text, style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.w900, color: color, letterSpacing: 0.5)),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isOnline;
  const _StatusBadge({required this.isOnline});

  @override
  Widget build(BuildContext context) {
    final color = isOnline ? AppColors.successEmerald : AppColors.dangerRose;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        isOnline ? 'LIVE' : 'OFFLINE',
        style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: color),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: color, letterSpacing: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityItem extends StatelessWidget {
  final String text;
  final String time;
  final Color color;

  const _ActivityItem({required this.text, required this.time, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(width: 4, height: 4, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ),
          const SizedBox(width: 6),
          Text(time, style: const TextStyle(fontSize: 9, color: Colors.white24)),
        ],
      ),
    );
  }
}
