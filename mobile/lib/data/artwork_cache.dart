import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Keeps track artwork on disk so the lock screen, Control Center and the car
/// can show it without depending on a remote fetch at the exact moment the
/// system asks for it.
///
/// iOS now-playing artwork is loaded lazily by the OS; a remote URL often
/// arrives too late, which is why some apps show a blank square there.
class ArtworkCache {
  ArtworkCache({HttpClient? client})
      : _client = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 10));

  final HttpClient _client;
  final Map<String, Uri> _resolved = {};
  final Set<String> _inFlight = {};

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'artwork'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Returns a local file URI for the artwork, or null if it cannot be fetched.
  Future<Uri?> forTrack(String id, String? url) async {
    if (url == null || url.isEmpty) return null;

    final cached = _resolved[id];
    if (cached != null && await File.fromUri(cached).exists()) return cached;
    if (_inFlight.contains(id)) return _resolved[id];

    _inFlight.add(id);
    try {
      final dir = await _dir();
      final file = File(p.join(dir.path, '$id.jpg'));
      if (await file.exists() && await file.length() > 1024) {
        final uri = file.uri;
        _resolved[id] = uri;
        return uri;
      }

      final request = await _client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 10));
      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }

      final sink = file.openWrite();
      try {
        await response.pipe(sink);
      } finally {
        await sink.close();
      }

      if (await file.length() < 1024) {
        await file.delete();
        return null;
      }
      final uri = file.uri;
      _resolved[id] = uri;
      return uri;
    } catch (_) {
      return null;
    } finally {
      _inFlight.remove(id);
    }
  }

  /// Drops artwork files that no longer belong to a cached track.
  Future<void> clear() async {
    try {
      final dir = await _dir();
      await dir.delete(recursive: true);
      _resolved.clear();
    } catch (_) {}
  }

  void dispose() => _client.close(force: true);
}
