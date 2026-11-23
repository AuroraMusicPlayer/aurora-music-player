import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';
import '../data/music_filter.dart';
import 'artwork.dart';
import 'mini_player.dart';

/// A real artist page: what you own, plus more from YouTube.
///
/// Album pages are deliberately absent — YouTube has no album concept, so any
/// "album" would be an invented grouping. Artists are a real entity.
class ArtistScreen extends StatefulWidget {
  const ArtistScreen({
    super.key,
    required this.services,
    required this.artist,
    this.thumbnail,
  });

  final AppServices services;
  final String artist;
  final String? thumbnail;

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  List<Track> _owned = const [];
  List<Track> _more = const [];
  bool _loadingOwned = true;
  bool _loadingMore = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final own = await widget.services.library.byArtist(widget.artist);
    if (!mounted) return;
    setState(() {
      _owned = own;
      _loadingOwned = false;
    });

    try {
      final results = await widget.services.source.search(widget.artist, limit: 20);
      final ownedIds = own.map((t) => t.id).toSet();
      final more = MusicFilter.songsOnly(results)
          .where((t) => !ownedIds.contains(t.id))
          .take(15)
          .toList(growable: false);
      for (final track in more) {
        await widget.services.library.remember(track);
      }
      if (!mounted) return;
      setState(() {
        _more = more;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  List<Track> get _playable => _owned.isNotEmpty ? _owned : _more;

  Future<void> _playAll({bool shuffle = false}) async {
    if (_playable.isEmpty) return;
    if (shuffle && !widget.services.handler.player.shuffleModeEnabled) {
      await widget.services.handler.toggleShuffle();
    } else if (!shuffle && widget.services.handler.player.shuffleModeEnabled) {
      await widget.services.handler.toggleShuffle();
    }
    await widget.services.handler.playTracks(_playable);
  }

  @override
  Widget build(BuildContext context) {
    final thumbnail = _owned.isNotEmpty
        ? _owned.first.thumbnail
        : (_more.isNotEmpty ? _more.first.thumbnail : widget.thumbnail);

    return Scaffold(
      appBar: AppBar(title: Text(widget.artist)),
      bottomNavigationBar: MiniPlayer(services: widget.services),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 96,
                    height: 96,
                    child: artworkForVideo(
                      _videoIdFrom(thumbnail),
                      placeholderColor: const Color(0xFF1E1E1E),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.artist,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_owned.length} in your library',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _playable.isEmpty ? null : () => _playAll(),
                    icon: const Icon(Icons.play_arrow),
                    label: Text('Play ${_playable.length}'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _playable.isEmpty
                      ? null
                      : () => _playAll(shuffle: true),
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Shuffle'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_loadingOwned && _loadingMore)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_owned.isNotEmpty) ...[
            _header('In your library'),
            for (var i = 0; i < _owned.length; i++)
              _trackTile(_owned[i], () => widget.services.handler
                  .playTracks(_owned, startIndex: i)),
          ],
          _header('More from YouTube'),
          if (_loadingMore)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_more.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text('Nothing else found for this artist.',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
            )
          else
            for (var i = 0; i < _more.length; i++)
              _trackTile(_more[i], () => widget.services.handler
                  .playTracks(_more, startIndex: i)),
        ],
      ),
    );
  }

  Widget _header(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      );

  Widget _trackTile(Track track, VoidCallback onTap) => ListTile(
        onTap: onTap,
        leading: SizedBox(
          width: 48,
          height: 48,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: artworkForVideo(track.id),
          ),
        ),
        title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${track.playCount > 0 ? 'played ${track.playCount}×' : track.artist}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        trailing: track.isCached
            ? const Icon(Icons.offline_pin_outlined,
                size: 16, color: Colors.greenAccent)
            : null,
      );

  /// The artwork widget keys off a video id; thumbnails are URLs, so pull it
  /// back out rather than plumbing ids through the whole artist model.
  String? _videoIdFrom(String? thumbnail) {
    if (thumbnail == null) return null;
    final match = RegExp(r'/vi/([A-Za-z0-9_-]{11})/').firstMatch(thumbnail);
    return match?.group(1);
  }
}
