import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Locations of ffmpeg.exe / ffprobe.exe.
class FfmpegTools {
  final String ffmpeg;
  final String ffprobe;
  const FfmpegTools(this.ffmpeg, this.ffprobe);

  /// Looks next to the app, in the given extra folders, then on PATH.
  static Future<FfmpegTools?> locate({List<String> extraDirs = const []}) async {
    final exe = Platform.isWindows ? '.exe' : '';
    final appDir = p.dirname(Platform.resolvedExecutable);
    final dirs = <String>[
      appDir,
      p.join(appDir, 'ffmpeg'),
      p.join(appDir, 'ffmpeg', 'bin'),
      for (final d in extraDirs) ...[d, p.join(d, 'bin')],
    ];
    for (final d in dirs) {
      final f = p.join(d, 'ffmpeg$exe');
      final pr = p.join(d, 'ffprobe$exe');
      if (await File(f).exists() && await File(pr).exists()) {
        return FfmpegTools(f, pr);
      }
    }
    // Fall back to PATH.
    try {
      final a = await Process.run('ffmpeg', ['-version']);
      final b = await Process.run('ffprobe', ['-version']);
      if (a.exitCode == 0 && b.exitCode == 0) {
        return const FfmpegTools('ffmpeg', 'ffprobe');
      }
    } catch (_) {}
    return null;
  }
}

/// What ffprobe tells us about a media file.
class ProbeResult {
  final double durationSec;
  final String formatName;
  final int formatBitRate;
  final String? vCodec;
  final String? vProfile;
  final String? pixFmt;
  final int width;
  final int height;
  final double fps;
  final int level;
  final int vBitRate;
  final String? aCodec;
  final int aChannels;

  ProbeResult({
    required this.durationSec,
    required this.formatName,
    required this.formatBitRate,
    this.vCodec,
    this.vProfile,
    this.pixFmt,
    this.width = 0,
    this.height = 0,
    this.fps = 0,
    this.level = 0,
    this.vBitRate = 0,
    this.aCodec,
    this.aChannels = 0,
  });

  bool get hasVideo => vCodec != null;

  /// H.264 8-bit 4:2:0 Main/Baseline profile, at most 1080p30, level 4.0, <= 15 Mbit/s.
  /// Enforcing Main or Baseline profile ensures hardware decoding compatibility across
  /// 100% of Android TVs (including Triton, Fire TV, and low-end TV boxes that fail on High profile).
  bool get videoCompatible {
    if (vCodec != 'h264') return false;
    if (pixFmt != 'yuv420p' && pixFmt != 'yuvj420p') return false;
    final prof = (vProfile ?? '').toLowerCase();
    if (!(prof == 'main' || prof.contains('baseline'))) return false;
    final longSide = width > height ? width : height;
    final shortSide = width > height ? height : width;
    if (longSide > 1920 || shortSide > 1080) return false;
    if (fps > 30.5) return false;
    if (level > 40) return false;
    final br = vBitRate > 0 ? vBitRate : formatBitRate;
    if (br > 15000000) return false;
    return true;
  }

  bool get audioCompatible => aCodec == null || (aCodec == 'aac' && aChannels <= 2);

  bool get containerMp4 => formatName.contains('mp4');

  /// Can be sent to TVs exactly as it is.
  bool get playableAsIs => hasVideo && videoCompatible && audioCompatible && containerMp4;

  static double _rate(String? r) {
    if (r == null || !r.contains('/')) return double.tryParse(r ?? '') ?? 0;
    final parts = r.split('/');
    final a = double.tryParse(parts[0]) ?? 0;
    final b = double.tryParse(parts[1]) ?? 0;
    return b == 0 ? 0 : a / b;
  }

  static int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

  factory ProbeResult.fromJson(Map<String, dynamic> j) {
    final format = Map<String, dynamic>.from((j['format'] as Map?) ?? {});
    final streams = ((j['streams'] as List?) ?? [])
        .map((s) => Map<String, dynamic>.from(s as Map))
        .toList();
    Map<String, dynamic>? v;
    Map<String, dynamic>? a;
    for (final s in streams) {
      final type = s['codec_type'];
      final disp = Map<String, dynamic>.from((s['disposition'] as Map?) ?? {});
      if (type == 'video' && v == null && _int(disp['attached_pic']) != 1) v = s;
      if (type == 'audio' && a == null) a = s;
    }
    var fps = _rate(v?['avg_frame_rate'] as String?);
    if (fps <= 0 || fps > 240) fps = _rate(v?['r_frame_rate'] as String?);
    return ProbeResult(
      durationSec: double.tryParse('${format['duration'] ?? ''}') ?? 0,
      formatName: '${format['format_name'] ?? ''}',
      formatBitRate: _int(format['bit_rate']),
      vCodec: v?['codec_name'] as String?,
      vProfile: v?['profile'] as String?,
      pixFmt: v?['pix_fmt'] as String?,
      width: _int(v?['width']),
      height: _int(v?['height']),
      fps: fps,
      level: _int(v?['level']),
      vBitRate: _int(v?['bit_rate']),
      aCodec: a?['codec_name'] as String?,
      aChannels: _int(a?['channels']),
    );
  }

  String describe() {
    final res = hasVideo ? '${width}x$height ${fps.toStringAsFixed(fps % 1 == 0 ? 0 : 2)}fps' : 'no video';
    return '${vCodec ?? '-'} ${vProfile ?? ''} $res, audio ${aCodec ?? 'none'}';
  }
}

Future<ProbeResult?> probeMedia(FfmpegTools tools, String path) async {
  try {
    final r = await Process.run(
      tools.ffprobe,
      ['-v', 'error', '-print_format', 'json', '-show_format', '-show_streams', path],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    ).timeout(const Duration(seconds: 60));
    if (r.exitCode != 0) return null;
    return ProbeResult.fromJson(Map<String, dynamic>.from(jsonDecode(r.stdout as String) as Map));
  } catch (_) {
    return null;
  }
}

enum JobStatus { queued, analyzing, converting, finalizing, done, failed, cancelled }

class TranscodeJob {
  final String id;
  final String sourcePath;

  /// File name the finished video gets inside the media folder.
  final String targetName;

  /// Library item this job replaces (existing file that TVs cannot play).
  final String? replaces;

  JobStatus status = JobStatus.queued;
  double progress = 0; // 0..1
  String mode = '';
  String? error;
  DateTime? startedAt;
  double outputDurationSec = 0;
  Process? _process;
  bool _cancelRequested = false;

  TranscodeJob({required this.id, required this.sourcePath, required this.targetName, this.replaces});

  String get displayName => p.basename(sourcePath);

  bool get isActive =>
      status == JobStatus.queued ||
      status == JobStatus.analyzing ||
      status == JobStatus.converting ||
      status == JobStatus.finalizing;

  Duration? get eta {
    if (startedAt == null || progress <= 0.02 || status != JobStatus.converting) return null;
    final elapsed = DateTime.now().difference(startedAt!).inMilliseconds;
    final total = elapsed / progress;
    return Duration(milliseconds: (total - elapsed).round());
  }
}

/// Converts videos one at a time into a format every TV can play.
class TranscodeQueue {
  final FfmpegTools tools;
  final String mediaDir;
  final void Function(TranscodeJob job) onUpdate;
  final void Function(TranscodeJob job, String outputPath) onDone;
  final void Function(TranscodeJob job) onFailed;

  final List<TranscodeJob> jobs = [];
  bool _running = false;
  int _counter = 0;

  TranscodeQueue({
    required this.tools,
    required this.mediaDir,
    required this.onUpdate,
    required this.onDone,
    required this.onFailed,
  });

  List<TranscodeJob> get activeJobs => jobs.where((j) => j.isActive).toList();

  bool isTargetTaken(String name) => activeJobs.any((j) => j.targetName == name);

  TranscodeJob add(String sourcePath, String targetName, {String? replaces}) {
    final job = TranscodeJob(
      id: 'job${++_counter}',
      sourcePath: sourcePath,
      targetName: targetName,
      replaces: replaces,
    );
    jobs.add(job);
    onUpdate(job);
    _pump();
    return job;
  }

  void cancel(TranscodeJob job) {
    job._cancelRequested = true;
    if (job.status == JobStatus.queued) {
      job.status = JobStatus.cancelled;
      onUpdate(job);
    }
    job._process?.kill();
  }

  void cancelAll() {
    for (final j in List<TranscodeJob>.from(jobs)) {
      if (j.isActive) cancel(j);
    }
  }

  /// Forget finished jobs so the panel only shows current work.
  void clearFinished() => jobs.removeWhere((j) => !j.isActive);

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final next = jobs.where((j) => j.status == JobStatus.queued).toList();
        if (next.isEmpty) break;
        await _run(next.first);
      }
    } finally {
      _running = false;
    }
  }

  String _tempPath(TranscodeJob job) => p.join(mediaDir, '.${job.targetName}.part');

  Future<void> _run(TranscodeJob job) async {
    final temp = _tempPath(job);
    try {
      job.status = JobStatus.analyzing;
      onUpdate(job);
      final info = await probeMedia(tools, job.sourcePath);
      if (info == null) throw 'Could not read this file (damaged or not a video).';
      if (!info.hasVideo) throw 'This file has no video stream.';

      final copyVideo = info.videoCompatible;
      final copyAudio = info.audioCompatible;
      job.mode = copyVideo
          ? (copyAudio ? 'Preparing for streaming' : 'Converting audio')
          : 'Converting video';

      final vf = StringBuffer(
          "scale=w='min(1920,iw)':h='min(1080,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2,setsar=1");
      if (info.fps > 30.5) vf.write(',fps=30');

      final args = <String>[
        '-hide_banner', '-nostdin', '-y',
        '-i', job.sourcePath,
        '-map', '0:v:0', '-map', '0:a:0?',
        '-sn', '-dn', '-map_metadata', '-1', '-map_chapters', '-1',
        if (copyVideo) ...['-c:v', 'copy'] else ...[
          '-c:v', 'libx264', '-preset', 'veryfast',
          '-profile:v', 'main', '-level:v', '4.0',
          '-pix_fmt', 'yuv420p',
          '-crf', '21', '-maxrate', '6M', '-bufsize', '12M',
          '-g', '60',
          '-vf', vf.toString(),
        ],
        if (copyAudio) ...['-c:a', 'copy'] else ...['-c:a', 'aac', '-b:a', '160k', '-ac', '2', '-ar', '48000'],
        '-movflags', '+faststart',
        '-f', 'mp4',
        '-progress', 'pipe:1', '-nostats',
        temp,
      ];

      job.status = JobStatus.converting;
      job.startedAt = DateTime.now();
      onUpdate(job);

      final proc = await Process.start(tools.ffmpeg, args);
      job._process = proc;
      final errTail = <String>[];
      final errSub = proc.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) {
        errTail.add(line);
        if (errTail.length > 15) errTail.removeAt(0);
      });
      final total = info.durationSec;
      var lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
      final outSub = proc.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) {
        if (line.startsWith('out_time_us=') || line.startsWith('out_time_ms=')) {
          final us = int.tryParse(line.split('=').last) ?? 0;
          if (total > 0 && us > 0) {
            job.progress = (us / 1e6 / total).clamp(0.0, 0.99);
          }
          final now = DateTime.now();
          if (now.difference(lastUpdate).inMilliseconds > 700) {
            lastUpdate = now;
            onUpdate(job);
          }
        } else if (line == 'progress=end') {
          // Moving the index to the front can take a while on big files.
          job.status = JobStatus.finalizing;
          job.progress = 0.99;
          onUpdate(job);
        }
      });

      final code = await proc.exitCode;
      await outSub.cancel();
      await errSub.cancel();
      job._process = null;

      if (job._cancelRequested) throw _Cancelled();
      if (code != 0) {
        throw 'ffmpeg failed (code $code): ${errTail.where((l) => l.trim().isNotEmpty).take(3).join(' | ')}';
      }

      job.status = JobStatus.finalizing;
      onUpdate(job);
      final outInfo = await probeMedia(tools, temp);
      if (outInfo == null || !outInfo.hasVideo) throw 'Converted file could not be verified.';
      job.outputDurationSec = outInfo.durationSec;

      final finalPath = p.join(mediaDir, job.targetName);
      final finalFile = File(finalPath);
      if (await finalFile.exists()) await finalFile.delete();
      await File(temp).rename(finalPath);

      job.status = JobStatus.done;
      job.progress = 1;
      onUpdate(job);
      onDone(job, finalPath);
    } catch (e) {
      try {
        final t = File(temp);
        if (await t.exists()) await t.delete();
      } catch (_) {}
      if (e is _Cancelled || job._cancelRequested) {
        job.status = JobStatus.cancelled;
        onUpdate(job);
      } else {
        job.status = JobStatus.failed;
        job.error = e.toString();
        onUpdate(job);
        onFailed(job);
      }
    }
  }
}

class _Cancelled implements Exception {}
