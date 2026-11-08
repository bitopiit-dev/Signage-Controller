import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import '../models/playlist_item.dart';

class MediaUtils {
  static const List<String> videoExtensions = [
    'mp4', 'mkv', 'mov', 'avi', 'webm', '3gp', 'm4v', 'ts', 'wmv', 'flv', 'mpg', 'mpeg',
    'vob', 'mts', 'm2ts', 'ogv', 'divx', 'rmvb', 'rm', 'f4v', 'asf', 'mxf', 'dv', 'hevc',
  ];
  static const List<String> imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];
  static const List<String> audioExtensions = ['mp3', 'wav', 'ogg', 'aac', 'm4a', 'flac'];
  static const List<String> pdfExtensions = ['pdf'];
  static const List<String> docExtensions = ['txt', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'rtf', 'csv'];

  static MediaType getMediaType(String filename) {
    final parts = filename.split('.');
    if (parts.length < 2) return MediaType.document;
    final ext = parts.last.toLowerCase();
    if (videoExtensions.contains(ext)) return MediaType.video;
    if (imageExtensions.contains(ext)) return MediaType.image;
    if (pdfExtensions.contains(ext)) return MediaType.pdf;
    if (audioExtensions.contains(ext)) return MediaType.audio;
    if (docExtensions.contains(ext)) return MediaType.document;
    return MediaType.document;
  }

  static Future<void> openFile(String filePath) async {
    try {
      if (Platform.isWindows) {
        await Process.run('start', [filePath], runInShell: true);
      } else if (Platform.isMacOS) {
        await Process.run('open', [filePath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [filePath]);
      }
    } catch (e) {
      debugPrint('Error opening file: $e');
    }
  }

  static Future<void> openUrl(String url) async {
    try {
      if (Platform.isWindows) {
        await Process.run('start', [url], runInShell: true);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      }
    } catch (e) {
      debugPrint('Error opening URL: $e');
    }
  }

  static List<String> get allSupportedExtensions => [
    ...videoExtensions,
    ...imageExtensions,
    ...audioExtensions,
    ...pdfExtensions,
    ...docExtensions,
  ];

  /// Default on-screen time for still content (images, PDFs, documents).
  static const int defaultStillSeconds = 15;

  static Future<int> detectDuration(String path, MediaType type) async {
    if (type == MediaType.video || type == MediaType.movie || type == MediaType.audio) {
      try {
        final controller = VideoPlayerController.file(File(path));
        await controller.initialize().timeout(const Duration(seconds: 10));
        final d = controller.value.duration.inSeconds;
        await controller.dispose();
        return d > 0 ? d : defaultStillSeconds;
      } catch (e) {
        // Not supported on this platform (e.g. Windows) - players will
        // report the real duration once they start playing the file.
        return defaultStillSeconds;
      }
    }
    return defaultStillSeconds;
  }

  /// Extracts the 11-char video id from any common YouTube URL form.
  static String? youtubeId(String? url) {
    if (url == null) return null;
    final u = url.trim();
    if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(u)) return u;
    final patterns = [
      RegExp(r'youtu\.be/([A-Za-z0-9_-]{11})'),
      RegExp(r'[?&]v=([A-Za-z0-9_-]{11})'),
      RegExp(r'/embed/([A-Za-z0-9_-]{11})'),
      RegExp(r'/shorts/([A-Za-z0-9_-]{11})'),
      RegExp(r'/live/([A-Za-z0-9_-]{11})'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(u);
      if (m != null) return m.group(1);
    }
    return null;
  }
}
