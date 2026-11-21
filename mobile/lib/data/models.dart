/// A track as the app knows it: YouTube metadata plus everything the app has
/// learned about how you listen to it.
class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.duration,
    this.thumbnail,
    this.audioPath,
    this.bytes = 0,
    this.cachedAt,
    this.cacheOrigin,
    this.playCount = 0,
    this.skipCount = 0,
    this.favorite = false,
    this.lastPlayed,
  });

  final String id;
  final String title;
  final String artist;
  final String? album;

  /// Seconds.
  final int? duration;
  final String? thumbnail;

  /// Set only when the audio lives on this device.
  final String? audioPath;
  final int bytes;
  final DateTime? cachedAt;

  /// `manual` (you asked for it) or `auto` (the app decided).
  final String? cacheOrigin;

  final int playCount;
  final int skipCount;
  final bool favorite;
  final DateTime? lastPlayed;

  bool get isCached => audioPath != null;

  Duration? get length => duration == null ? null : Duration(seconds: duration!);

  /// Plays minus early skips. Drives both auto-cache and ordering.
  int get affinity => playCount - skipCount;

  factory Track.fromResolverJson(Map<String, dynamic> json) => Track(
        id: json['id'] as String,
        title: (json['title'] as String?) ?? 'Unknown title',
        artist: (json['artist'] as String?) ?? 'Unknown artist',
        album: json['album'] as String?,
        duration: (json['duration'] as num?)?.toInt(),
        thumbnail: json['thumbnail'] as String?,
      );

  factory Track.fromRow(Map<String, Object?> row) => Track(
        id: row['id'] as String,
        title: row['title'] as String,
        artist: row['artist'] as String,
        album: row['album'] as String?,
        duration: (row['duration'] as num?)?.toInt(),
        thumbnail: row['thumbnail'] as String?,
        audioPath: row['audio_path'] as String?,
        bytes: (row['bytes'] as num?)?.toInt() ?? 0,
        cachedAt: _date(row['cached_at']),
        cacheOrigin: row['cache_origin'] as String?,
        playCount: (row['play_count'] as num?)?.toInt() ?? 0,
        skipCount: (row['skip_count'] as num?)?.toInt() ?? 0,
        favorite: ((row['favorite'] as num?)?.toInt() ?? 0) == 1,
        lastPlayed: _date(row['last_played']),
      );

  static DateTime? _date(Object? millis) =>
      millis == null ? null : DateTime.fromMillisecondsSinceEpoch((millis as num).toInt());

  Map<String, Object?> toRow() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'duration': duration,
        'thumbnail': thumbnail,
        'audio_path': audioPath,
        'bytes': bytes,
        'cached_at': cachedAt?.millisecondsSinceEpoch,
        'cache_origin': cacheOrigin,
        'play_count': playCount,
        'skip_count': skipCount,
        'favorite': favorite ? 1 : 0,
        'last_played': lastPlayed?.millisecondsSinceEpoch,
      };

  Track copyWith({
    String? audioPath,
    int? bytes,
    DateTime? cachedAt,
    String? cacheOrigin,
    int? playCount,
    int? skipCount,
    bool? favorite,
    DateTime? lastPlayed,
  }) =>
      Track(
        id: id,
        title: title,
        artist: artist,
        album: album,
        duration: duration,
        thumbnail: thumbnail,
        audioPath: audioPath ?? this.audioPath,
        bytes: bytes ?? this.bytes,
        cachedAt: cachedAt ?? this.cachedAt,
        cacheOrigin: cacheOrigin ?? this.cacheOrigin,
        playCount: playCount ?? this.playCount,
        skipCount: skipCount ?? this.skipCount,
        favorite: favorite ?? this.favorite,
        lastPlayed: lastPlayed ?? this.lastPlayed,
      );
}
