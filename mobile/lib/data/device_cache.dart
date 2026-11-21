import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../settings.dart';
import 'library.dart';
import 'models.dart';
import 'youtube_source.dart';

/// Copies audio onto the device so it plays with no network at all.
///
/// Downloads use a plain [HttpClient] because the extractor library's own
/// downloader stalls on googlevideo's 302 redirect. A plain client follows it
/// and gets a clean `audio/mp4` response with Range support.
class DeviceCache {
  DeviceCache({
    required this.library,
    required this.source,
    required this.settings,
    HttpClient? client,
  }) : _client = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 15));

  final Library library;
  final YouTubeSource source;
  final Settings settings;
  final HttpClient _client;

  final Set<String> _downloading = {};

  bool isDownloading(String id) => _downloading.contains(id);

  Future<Directory> _audioDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'audio'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Downloaded files must not count against the user's iCloud backup.
  Future<void> _excludeFromBackup(File file) async {
    if (!Platform.isIOS) return;
    try {
      await Process.run('xattr', ['-w', 'com.apple.MobileBackup', '1', file.path]);
    } catch (_) {
      // Cosmetic: the file still plays, it may just be included in a backup.
    }
  }

  Future<bool> _networkAllowsDownload() async {
    if (!settings.wifiOnly) return true;
    final results = await Connectivity().checkConnectivity();
    return results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);
  }

  /// Returns the updated track, or null when the download was skipped.
  Future<Track?> download(Track track, {String origin = 'manual', bool force = false}) async {
    if (track.isCached) return track;
    if (_downloading.contains(track.id)) return null;
    if (!force && !await _networkAllowsDownload()) return null;

    _downloading.add(track.id);
    File? partial;
    try {
      if (await library.byId(track.id) == null) await library.remember(track);

      final dir = await _audioDir();
      final target = File(p.join(dir.path, '${track.id}.m4a'));
      partial = File('${target.path}.part');

      final resolved = await source.stream(track.id);
      await _fetchToFile(resolved.url, partial);

      final length = await partial.length();
      if (length < 1024) {
        throw const YouTubeSourceException('Downloaded file looks truncated');
      }
      final expected = resolved.bytes;
      if (expected != null && expected > 0 && (length - expected).abs() > expected * 0.05) {
        // Wrong length usually means a 403 page got written instead of audio.
        throw YouTubeSourceException(
          'Incomplete download (${(length / 1048576).toStringAsFixed(1)} MB of '
          '${(expected / 1048576).toStringAsFixed(1)} MB)',
        );
      }

      await partial.rename(target.path);
      await _excludeFromBackup(target);

      await library.markCached(track.id, target.path, length, origin);
      await enforceBudget();
      return await library.byId(track.id);
    } catch (_) {
      try {
        if (partial != null && await partial.exists()) await partial.delete();
      } catch (_) {}
      rethrow;
    } finally {
      _downloading.remove(track.id);
    }
  }

  Future<void> _fetchToFile(String url, File destination) async {
    var uri = Uri.parse(url);

    for (var hop = 0; hop < 4; hop++) {
      final request = await _client.getUrl(uri);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-');
      final response = await request.close();

      // Follow the redirect chain ourselves so a stale signed URL fails loudly
      // instead of writing an error page into the cache.
      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null) throw const YouTubeSourceException('Bad redirect');
        uri = uri.resolve(location);
        continue;
      }

      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        final body = await utf8.decoder.bind(response).join();
        throw YouTubeSourceException(
          'HTTP ${response.statusCode}: ${body.substring(0, body.length.clamp(0, 120))}',
        );
      }

      final sink = destination.openWrite();
      try {
        await response.pipe(sink);
      } finally {
        await sink.close();
      }
      return;
    }

    throw const YouTubeSourceException('Too many redirects');
  }

  Future<void> remove(Track track) async {
    final path = track.audioPath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    await library.clearCached(track.id);
  }

  /// Drops the least recently played auto-cached tracks until the cache fits
  /// the configured budget. Manual downloads and favourites are never touched.
  Future<void> enforceBudget() async {
    var total = await library.cachedBytes();
    if (total <= settings.cacheBudgetBytes) return;

    for (final track in await library.evictable()) {
      if (total <= settings.cacheBudgetBytes) break;
      await remove(track);
      total -= track.bytes;
    }
  }

  Future<int> usageBytes() => library.cachedBytes();

  void dispose() => _client.close(force: true);
}
