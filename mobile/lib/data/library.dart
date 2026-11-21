import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// SQLite-backed track table. Every track the app has ever seen lives here,
/// whether or not its audio is cached on the device.
class Library {
  Library(this._db);

  final Database _db;

  static Future<Library> open() async {
    final path = p.join(await getDatabasesPath(), 'aurora.db');
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
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
      },
    );
    return Library(db);
  }

  Future<Track?> byId(String id) async {
    final rows = await _db.query('tracks', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Track.fromRow(rows.first);
  }

  /// Insert metadata from the resolver without clobbering playback stats.
  Future<void> remember(Track track) async {
    await _db.rawInsert('''
      INSERT INTO tracks(id, title, artist, album, duration, thumbnail)
      VALUES(?, ?, ?, ?, ?, ?)
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

  Future<int> cachedBytes() async {
    final result = await _db.rawQuery(
        'SELECT COALESCE(SUM(bytes), 0) AS total FROM tracks WHERE audio_path IS NOT NULL');
    return (result.first['total'] as num?)?.toInt() ?? 0;
  }

  Future<void> close() => _db.close();
}
