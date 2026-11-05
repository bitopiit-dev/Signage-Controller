import 'package:flutter/material.dart';

/// Live status of one player (TV) as reported through POST /status.
class DeviceStatus {
  final String id;
  String name;
  String ip;
  String? filename;
  int positionMs;
  int durationMs;
  String type;
  bool isPaused;
  String state; // playing | paused | buffering | standby | idle | error | connecting
  String platform;
  String appVersion;
  String? lastError;
  String? screen;
  int lastSeenMs;
  final int firstSeenMs;

  DeviceStatus({
    required this.id,
    required this.name,
    required this.ip,
    required this.firstSeenMs,
    required this.lastSeenMs,
    this.filename,
    this.positionMs = 0,
    this.durationMs = 0,
    this.type = '',
    this.isPaused = false,
    this.state = 'idle',
    this.platform = '',
    this.appVersion = '',
    this.lastError,
    this.screen,
  });

  static const int offlineAfterMs = 8000;

  bool isOnline([int? nowMs]) =>
      (nowMs ?? DateTime.now().millisecondsSinceEpoch) - lastSeenMs <
      offlineAfterMs;

  void updateFrom(Map<String, dynamic> data, String remoteIp, int nowMs) {
    ip = remoteIp;
    lastSeenMs = nowMs;
    name = (data['deviceName'] as String?)?.trim().isNotEmpty == true
        ? data['deviceName'] as String
        : name;
    filename = data['filename'] as String?;
    final posMs = (data['positionMs'] as num?)?.toInt();
    final pos = (data['position'] as num?)?.toInt();
    positionMs = posMs ?? ((pos ?? 0) * 1000);
    final durMs = (data['durationMs'] as num?)?.toInt();
    final dur = (data['duration'] as num?)?.toInt();
    durationMs = durMs ?? ((dur ?? 0) * 1000);
    type = (data['type'] ?? '').toString();
    isPaused = data['isPaused'] == true;
    state = (data['state'] ?? (isPaused ? 'paused' : 'playing')).toString();
    platform = (data['platform'] ?? platform).toString();
    appVersion = (data['appVersion'] ?? appVersion).toString();
    lastError = data['lastError'] as String?;
    screen = data['screen'] as String?;
  }
}

class ActivityEntry {
  final String text;
  final Color color;
  final DateTime time;
  ActivityEntry(this.text, this.color) : time = DateTime.now();
}

String timeAgo(int millisAgo) {
  final s = (millisAgo / 1000).floor();
  if (s < 2) return 'just now';
  if (s < 60) return '${s}s ago';
  final m = s ~/ 60;
  if (m < 60) return '${m}m ago';
  return '${m ~/ 60}h ago';
}
