import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/recommendations.dart';

/// Square artwork tile used across the home feed.
class ArtworkCard extends StatelessWidget {
  const ArtworkCard({
    super.key,
    required this.track,
    required this.onTap,
    this.width = 150,
    this.round = false,
    this.showArtist = true,
  });

  final Track track;
  final VoidCallback onTap;
  final double width;
  final bool round;
  final bool showArtist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(round ? width : 8);

    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: radius,
                  child: SizedBox(
                    width: width,
                    height: width,
                    child: _artwork(),
                  ),
                ),
                if (track.isCached)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.offline_pin_outlined,
                          size: 14, color: Colors.greenAccent),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              track.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                height: 1.25,
              ),
            ),
            if (showArtist) ...[
              const SizedBox(height: 2),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _artwork() {
    if (track.thumbnail == null) {
      return const ColoredBox(color: Color(0xFF1E1E1E));
    }
    return Image.network(
      track.thumbnail!,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF1E1E1E)),
    );
  }
}

/// A titled horizontal row of [ArtworkCard]s.
class ShelfView extends StatelessWidget {
  const ShelfView({
    super.key,
    required this.shelf,
    required this.onPlay,
  });

  final HomeShelf shelf;

  /// Called with the tapped index inside the shelf, so playback continues
  /// through the row rather than jumping back to the home feed.
  final void Function(List<Track> tracks, int index) onPlay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
          child: Text(
            shelf.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
          ),
        ),
        if (shelf.subtitle != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              shelf.subtitle!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.white54),
            ),
          ),
        SizedBox(
          height: shelf.tracks.isEmpty
              ? 0
              : (shelf.round ? 150 + 46 : 150 + (shelf.showArtists ? 62 : 34)),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: shelf.tracks.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              return ArtworkCard(
                track: shelf.tracks[index],
                round: shelf.round,
                showArtist: shelf.showArtists,
                onTap: () => onPlay(shelf.tracks, index),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Circular artist card, the way YouTube Music and Spotify show people.
class ArtistCircle extends StatelessWidget {
  const ArtistCircle({super.key, required this.artist, required this.onTap});

  final ArtistRef artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(52),
        child: Column(
          children: [
            ClipOval(
              child: SizedBox(
                width: 96,
                height: 96,
                child: artist.thumbnail == null
                    ? const ColoredBox(
                        color: Color(0xFF1E1E1E),
                        child: Icon(Icons.person, color: Colors.white38),
                      )
                    : Image.network(artist.thumbnail!, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const ColoredBox(
                            color: Color(0xFF1E1E1E),
                            child: Icon(Icons.person, color: Colors.white38))),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              artist.name,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small progress bar under the mini player.
class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({super.key, required this.position, required this.duration});

  final Duration position;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final value = duration.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    return SizedBox(
      height: 2,
      child: LinearProgressIndicator(
        value: value,
        backgroundColor: Colors.white12,
        valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
