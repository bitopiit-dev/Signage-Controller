enum MediaType {
  video,
  image,
  pdf,
  audio,
  document,
  youtube,
  movie,
}

enum TransitionType {
  none,
  fade,
  slide,
  zoom,
  flip,
}

enum LibraryViewMode {
  icons,
  list,
  detailedList,
  pictureFlow,
}

class PlaylistItem {
  final String filename;
  final MediaType type;
  final int durationSeconds;
  final double volume;
  final TransitionType transition;
  final String? url;

  PlaylistItem({
    required this.filename,
    required this.type,
    this.durationSeconds = 10,
    this.volume = 1.0,
    this.transition = TransitionType.fade,
    this.url,
  });

  /// True for items whose real length comes from the media itself
  /// (video/audio/youtube) rather than from [durationSeconds].
  bool get isTimeBased =>
      type == MediaType.video ||
      type == MediaType.movie ||
      type == MediaType.audio ||
      type == MediaType.youtube;

  factory PlaylistItem.fromJson(Map<String, dynamic> j) {
    MediaType type = MediaType.document;
    final rawType = j['type']?.toString();
    for (final t in MediaType.values) {
      if (t.name == rawType) type = t;
    }
    TransitionType transition = TransitionType.fade;
    final rawTr = j['transition']?.toString();
    for (final t in TransitionType.values) {
      if (t.name == rawTr) transition = t;
    }
    return PlaylistItem(
      filename: (j['filename'] ?? 'unknown').toString(),
      type: type,
      durationSeconds: (j['durationSeconds'] as num?)?.toInt() ?? 10,
      volume: ((j['volume'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 1.0),
      transition: transition,
      url: j['url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'filename': filename,
      'type': type.name,
      'durationSeconds': durationSeconds,
      'volume': volume,
      'transition': transition.name,
      'url': url,
    };
  }

  PlaylistItem copyWith({
    double? volume,
    int? durationSeconds,
    TransitionType? transition,
  }) {
    return PlaylistItem(
      filename: filename,
      type: type,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      volume: volume ?? this.volume,
      transition: transition ?? this.transition,
      url: url,
    );
  }
}

String mediaTypeToString(MediaType t) {
  switch (t) {
    case MediaType.video: return 'Video';
    case MediaType.image: return 'Image';
    case MediaType.pdf: return 'PDF';
    case MediaType.audio: return 'Audio';
    case MediaType.document: return 'Doc';
    case MediaType.youtube: return 'YouTube';
    case MediaType.movie: return 'Movie';
  }
}

String transitionTypeToString(TransitionType t) {
  return t.name[0].toUpperCase() + t.name.substring(1);
}

String formatSeconds(int totalSeconds) {
  if (totalSeconds < 0) totalSeconds = 0;
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  if (h > 0) return '${two(h)}:${two(m)}:${two(s)}';
  return '${two(m)}:${two(s)}';
}
