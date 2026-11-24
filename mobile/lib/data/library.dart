import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// SQLite-backed track table. Every track the app has ever seen lives here,
/// whether or not its audio is cached on the device.
class Library {
  Library(this._db);

  final Database _db;

  static Future<Library> open({String? directory}) async {
    final base = directory ?? await getDatabasesPath();
    final path = p.join(base, 'aurora.db');
    final db = await openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await _createTracks(db);
        await _createPlaylists(db);
        await _createSync(db);
        await db.execute('ALTER TABLE tracks ADD COLUMN added_at INTEGER');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createPlaylists(db);
        if (oldVersion < 3) await _createSync(db);
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE tracks ADD COLUMN added_at INTEGER');
          await db.execute(
              'UPDATE tracks SET added_at = COALESCE(last_played, 0)');
        }
      },
    );
    return Library(db);
  }

  static Future<void> _createTracks(Database db) async {
    await db.execute('''
      CREATE TABLE tracks(
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        album TEXT,
        duration INTEGER,
        thumbnail TEXT,
        audio_path TEXT,
        bytes INTEGER NOT NULL DEFAULT 0,
        cached_at INTEGER,
        cache_origin TEXT,
        play_count INTEGER NOT NULL DEFAULT 0,
        skip_count INTEGER NOT NULL DEFAULT 0,
        favorite INTEGER NOT NULL DEFAULT 0,
        last_played INTEGER
      )
    ''');
    await db.execute('CREATE INDEX tracks_last_played ON tracks(last_played DESC)');
  }

  static Future<void> _createPlaylists(Database db) async {
    await db.execute('''
      CREATE TABLE playlists(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE playlist_tracks(
        playlist_id INTEGER NOT NULL,
        track_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        PRIMARY KEY (playlist_id, track_id)
      )
    ''');
    await db.execute(
        'CREATE INDEX playlist_tracks_order ON playlist_tracks(playlist_id, position)');
  }

  /// Link between local rows and their YouTube Music counterparts.
  static Future<void> _createSync(Database db) async {
    await db.execute('ALTER TABLE playlists ADD COLUMN youtube_id TEXT');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_state(
        kind TEXT NOT NULL,
        key TEXT NOT NULL,
        value TEXT,
        PRIMARY KEY (kind, key)
      )
    ''');
  }

  Future<Track?> byId(String id) async {
    final rows = await _db.query('tracks', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Track.fromRow(rows.first);
  }

  /// Insert metadata from the resolver without clobbering playback stats.
  Future<void> remember(Track track) async {
    await _db.rawInsert('''
      INSERT INTO tracks(id, title, artist, album, duration, thumbnail, added_at)
      VALUES(?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        title = excluded.title,
        artist = excluded.artist,
        album = excluded.album,
        duration = excluded.duration,
        thumbnail = excluded.thumbnail
    ''', [
      track.id,
      track.title,
      track.artist,
      track.album,
      track.duration,
      track.thumbnail,
      DateTime.now().millisecondsSinceEpoch,
    ]);
  }

  Future<void> recordPlay(String id) async {
    await _db.rawUpdate('''
      UPDATE tracks
      SET play_count = play_count + 1, last_played = ?
      WHERE id = ?
    ''', [DateTime.now().millisecondsSinceEpoch, id]);
  }

  Future<void> recordSkip(String id) async {
    await _db.rawUpdate('UPDATE tracks SET skip_count = skip_count + 1 WHERE id = ?', [id]);
  }

  Future<void> setFavorite(String id, bool favorite) async {
    await _db.update('tracks', {'favorite': favorite ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markCached(String id, String path, int bytes, String origin) async {
    await _db.update(
      'tracks',
      {
        'audio_path': path,
        'bytes': bytes,
        'cached_at': DateTime.now().millisecondsSinceEpoch,
        'cache_origin': origin,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearCached(String id) async {
    await _db.update(
      'tracks',
      {'audio_path': null, 'bytes': 0, 'cached_at': null, 'cache_origin': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Everything you hearted, whether or not it is cached.
  Future<List<Track>> favorites({int limit = 500}) async {
    final rows = await _db.query(
      'tracks',
      where: 'favorite = 1',
      orderBy: 'last_played DESC, title ASC',
      limit: limit,
    );
    return rows.map(Track.fromRow).toList(growable: false);
  }

  Future<int> favoriteCount() async {
    final result = await _db
        .rawQuery('SELECT COUNT(*) AS n FROM tracks WHERE favorite = 1');
    return (result.first['n'] as num?)?.toInt() ?? 0;
  }

  /// Cached tracks, optionally filtered by how they got here:
  /// `auto` (the app decided) or `manual` (you asked).
  Future<List<Track>> offline({String? origin}) async {
    final rows = await _db.query(
      'tracks',
      where: origin == null
          ? 'audio_path IS NOT NULL'
          : 'audio_path IS NOT NULL AND cache_origin = ?',
      whereArgs: origin == null ? null : [origin],
      orderBy: 'cached_at DESC',
    );
    return rows.map(Track.fromRow).toList(growable: false);
  }

  Future<int> offlineBytes({String? origin}) async {
    final result = await _db.rawQuery(
      origin == null
          ? 'SELECT COALESCE(SUM(bytes),0) AS total FROM tracks WHERE audio_path IS NOT NULL'
          : 'SELECT COALESCE(SUM(bytes),0) AS total FROM tracks WHERE audio_path IS NOT NULL AND cache_origin = ?',
      origin == null ? null : [origin],
    );
    return (result.first['total'] as num?)?.toInt() ?? 0;
  }

  Future<List<Track>> cached() async {
    final rows = await _db.query('tracks',
        where: 'audio_path IS NOT NULL', orderBy: 'last_played DESC');
    return rows.map(Track.fromRow).toList(growable: false);
  }

  /// Cached tracks that are safe to evict: auto-cached, never favourited,
  /// least recently played first.
  Future<List<Track>> evictable() async {
    final rows = await _db.query(
      'tracks',
      where: "audio_path IS NOT NULL AND favorite = 0 AND cache_origin = 'auto'",
      orderBy: 'last_played ASC',
    );
    return rows.map(Track.fromRow).toList(growable: false);
  }

  Future<List<Track>> recent({int limit = 50}) async {
    final rows = await _db.query('tracks',
        where: 'last_played IS NOT NULL',
        orderBy: 'last_played DESC',
        limit: limit);
    return rows.map(Track.fromRow).toList(growable: false);
  }

  /* ---------------------------- smart lists ----------------------------- */

  Future<List<Track>> recentlyAdded({int limit = 100}) async {
    final rows = await _db.query('tracks',
        orderBy: 'added_at DESC, rowid DESC', limit: limit);
    return rows.map(Track.fromRow).toList(growable: false);
  }

  Future<List<Track>> downloadedThisMonth({int limit = 100}) async {
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;
    final rows = await _db.query(
      'tracks',
      where: 'audio_path IS NOT NULL AND cached_at >= ?',
      whereArgs: [cutoff],
      orderBy: 'cached_at DESC',
      limit: limit,
    );
    return rows.map(Track.fromRow).toList(growable: false);
  }

  /// Played, never saved: the queue for a long drive or a flight.
  Future<List<Track>> readyForOffline({int limit = 100}) async {
    final rows = await _db.query(
      'tracks',
      where: 'play_count > 0 AND audio_path IS NULL',
      orderBy: 'play_count DESC',
      limit: limit,
    );
    return rows.map(Track.fromRow).toList(growable: false);
  }

  Future<List<Track>> byArtist(String artist, {int limit = 100}) async {
    final rows = await _db.query(
      'tracks',
      where: 'LOWER(artist) = LOWER(?)',
      whereArgs: [artist],
      orderBy: 'play_count DESC, title ASC',
      limit: limit,
    );
    return rows.map(Track.fromRow).toList(growable: false);
  }

  Future<int> tracksByArtist(String artist) async {
    final rows = await _db.rawQuery(
        'SELECT COUNT(*) AS n FROM tracks WHERE LOWER(artist) = LOWER(?)', [artist]);
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  /// Most played first, for the home feed.
  Future<List<Track>> mostPlayed({int limit = 25}) async {
    final rows = await _db.query(
      'tracks',
      where: 'play_count > 0',
      orderBy: 'play_count DESC, last_played DESC',
      limit: limit,
    );
    return rows.map(Track.fromRow).toList(growable: false);
  }

  /// Tracks you liked once but have not touched in [days] — the cheapest real
  /// recommendation the app can make, because it needs no network at all.
  Future<List<Track>> worthAnotherListen({int limit = 12, int days = 7}) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: days))
        .millisecondsSinceEpoch;
    final rows = await _db.query(
      'tracks',
      where: 'play_count > 0 AND last_played IS NOT NULL AND last_played < ?',
      whereArgs: [cutoff],
      orderBy: 'play_count DESC, last_played ASC',
      limit: limit,
    );
    return rows.map(Track.fromRow).toList(growable: false);
  }

  /// artist → (plays − skips), used to rank search results by taste.
  Future<Map<String, int>> artistScores() async {
    final rows = await _db.rawQuery('''
      SELECT LOWER(artist) AS artist,
             SUM(play_count) - SUM(skip_count) AS score
      FROM tracks
      WHERE play_count > 0
      GROUP BY LOWER(artist)
      HAVING score > 0
      ORDER BY score DESC
      LIMIT 200
    ''');
    return {
      for (final row in rows)
        if (row['artist'] is String)
          (row['artist'] as String): (row['score'] as num?)?.toInt() ?? 0,
    };
  }

  /// Artists with their most recent artwork, for the circular home row.
  Future<List<ArtistRef>> artistRefs({int limit = 12}) async {
    final rows = await _db.rawQuery('''
      SELECT artist,
             (SELECT t2.thumbnail FROM tracks t2
               WHERE t2.artist = tracks.artist AND t2.thumbnail IS NOT NULL
               ORDER BY t2.last_played DESC LIMIT 1) AS thumbnail,
             SUM(play_count) AS plays
      FROM tracks
      WHERE play_count > 0 AND artist <> 'Unknown artist'
      GROUP BY artist
      ORDER BY plays DESC, artist ASC
      LIMIT ?
    ''', [limit]);

    return rows
        .map((r) => ArtistRef(
              name: (r['artist'] as String?) ?? '',
              thumbnail: r['thumbnail'] as String?,
              plays: (r['plays'] as num?)?.toInt() ?? 0,
            ))
        .where((a) => a.name.isNotEmpty)
        .toList(growable: false);
  }

  /// Artists ranked by total plays — the seed for "Because you played…".
  Future<List<String>> topArtists({int limit = 5, int minPlays = 1}) async {
    final rows = await _db.rawQuery('''
      SELECT artist, SUM(play_count) AS plays
      FROM tracks
      WHERE play_count >= ?
      GROUP BY artist
      ORDER BY plays DESC
      LIMIT ?
    ''', [minPlays, limit]);
    return rows
        .map((r) => (r['artist'] as String?) ?? '')
        .where((a) => a.isNotEmpty && a != 'Unknown artist')
        .toList(growable: false);
  }

  Future<int> cachedBytes() async {
    final result = await _db.rawQuery(
        'SELECT COALESCE(SUM(bytes), 0) AS total FROM tracks WHERE audio_path IS NOT NULL');
    return (result.first['total'] as num?)?.toInt() ?? 0;
  }

  /* ----------------------------- playlists ------------------------------ */

  Future<List<Playlist>> playlists() async {
    final rows = await _db.rawQuery('''
      SELECT p.id, p.name, p.created_at, p.youtube_id,
             COUNT(pt.track_id) AS track_count,
             (SELECT t.thumbnail FROM playlist_tracks pt2
                JOIN tracks t ON t.id = pt2.track_id
               WHERE pt2.playlist_id = p.id
               ORDER BY pt2.position LIMIT 1) AS thumbnail
      FROM playlists p
      LEFT JOIN playlist_tracks pt ON pt.playlist_id = p.id
      GROUP BY p.id
      ORDER BY p.created_at DESC
    ''');
    return rows.map(Playlist.fromRow).toList(growable: false);
  }

  Future<void> setPlaylistYoutubeId(int id, String youtubeId) async {
    await _db.update('playlists', {'youtube_id': youtubeId},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<Playlist?> playlistByYoutubeId(String youtubeId) async {
    final rows = await _db.query('playlists',
        where: 'youtube_id = ?', whereArgs: [youtubeId], limit: 1);
    if (rows.isEmpty) return null;
    return Playlist.fromRow(rows.first);
  }

  Future<String?> syncValue(String kind, String key) async {
    final rows = await _db.query('sync_state',
        where: 'kind = ? AND key = ?', whereArgs: [kind, key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSyncValue(String kind, String key, String? value) async {
    await _db.insert(
      'sync_state',
      {'kind': kind, 'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Songs liked in YouTube Music, most recent first.
  ///
  /// Rows are written by the sync, so this is a local read: opening Home never
  /// waits on the network for the shelf to appear.
  Future<List<Track>> youtubeLikes({int limit = 40}) async {
    final rows = await _db.rawQuery('''
      SELECT t.* FROM sync_state s
      JOIN tracks t ON t.id = s.key
      WHERE s.kind = 'youtube_like'
      ORDER BY s.value DESC
      LIMIT ?
    ''', [limit]);
    return rows.map(Track.fromRow).toList(growable: false);
  }

  Future<int> createPlaylist(String name) async {
    return _db.insert('playlists', {
      'name': name.trim(),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> renamePlaylist(int id, String name) async {
    await _db.update('playlists', {'name': name.trim()},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deletePlaylist(int id) async {
    await _db.delete('playlist_tracks', where: 'playlist_id = ?', whereArgs: [id]);
    await _db.delete('playlists', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Track>> playlistTracks(int id) async {
    final rows = await _db.rawQuery('''
      SELECT t.* FROM playlist_tracks pt
      JOIN tracks t ON t.id = pt.track_id
      WHERE pt.playlist_id = ?
      ORDER BY pt.position
    ''', [id]);
    return rows.map(Track.fromRow).toList(growable: false);
  }

  Future<void> addToPlaylist(int playlistId, String trackId) async {
    final existing = await _db.query('playlist_tracks',
        where: 'playlist_id = ? AND track_id = ?',
        whereArgs: [playlistId, trackId],
        limit: 1);
    if (existing.isNotEmpty) return;

    final result = await _db.rawQuery(
        'SELECT COALESCE(MAX(position), -1) + 1 AS next FROM playlist_tracks WHERE playlist_id = ?',
        [playlistId]);
    final next = (result.first['next'] as num?)?.toInt() ?? 0;
    await _db.insert('playlist_tracks', {
      'playlist_id': playlistId,
      'track_id': trackId,
      'position': next,
    });
  }

  /// Moves one track inside a playlist and rewrites the positions.
  Future<void> movePlaylistTrack(int playlistId, int oldIndex, int newIndex) async {
    final tracks = await playlistTracks(playlistId);
    if (oldIndex < 0 || oldIndex >= tracks.length) return;
    if (newIndex > oldIndex) newIndex -= 1;

    final track = tracks.removeAt(oldIndex);
    tracks.insert(newIndex.clamp(0, tracks.length), track);

    final batch = _db.batch();
    for (var i = 0; i < tracks.length; i++) {
      batch.update(
        'playlist_tracks',
        {'position': i},
        where: 'playlist_id = ? AND track_id = ?',
        whereArgs: [playlistId, tracks[i].id],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> removeFromPlaylist(int playlistId, String trackId) async {
    await _db.delete('playlist_tracks',
        where: 'playlist_id = ? AND track_id = ?',
        whereArgs: [playlistId, trackId]);
  }

  /// Creates a playlist from already-remembered tracks (playlist import).
  Future<int> createPlaylistWithTracks(String name, List<Track> tracks) async {
    final id = await createPlaylist(name);
    for (var i = 0; i < tracks.length; i++) {
      await _db.insert('playlist_tracks', {
        'playlist_id': id,
        'track_id': tracks[i].id,
        'position': i,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    return id;
  }

  Future<void> close() => _db.close();
}
