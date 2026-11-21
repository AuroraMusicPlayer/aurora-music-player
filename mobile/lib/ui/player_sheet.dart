import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';
import 'playlist_dialogs.dart';

Future<void> showPlayerSheet(BuildContext context, AppServices services) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFF101010),
    builder: (_) => PlayerSheet(services: services),
  );
}

class PlayerSheet extends StatelessWidget {
  const PlayerSheet({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Track?>(
      valueListenable: services.handler.activeTrack,
      builder: (context, track, _) {
        if (track == null) {
          return const SizedBox(height: 200, child: Center(child: Text('Nothing playing')));
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: track.thumbnail == null
                      ? const ColoredBox(color: Color(0xFF1E1E1E))
                      : Image.network(track.thumbnail!, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const ColoredBox(color: Color(0xFF1E1E1E))),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                track.title,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 16),
              _PositionBar(services: services),
              const SizedBox(height: 4),
              _Controls(services: services),
              const SizedBox(height: 8),
              _Actions(services: services, track: track),
              const SizedBox(height: 12),
              _CacheRow(services: services, track: track),
            ],
          ),
        );
      },
    );
  }
}

class _PositionBar extends StatelessWidget {
  const _PositionBar({required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: services.handler.player.positionStream,
      builder: (context, positionSnapshot) {
        return StreamBuilder<Duration?>(
          stream: services.handler.player.durationStream,
          builder: (context, durationSnapshot) {
            final duration = durationSnapshot.data ?? Duration.zero;
            final position = positionSnapshot.data ?? Duration.zero;
            final max = duration.inMilliseconds.toDouble();
            final value = position.inMilliseconds.toDouble().clamp(0, max <= 0 ? 1 : max);

            return Column(
              children: [
                Slider(
                  value: max <= 0 ? 0 : value.toDouble(),
                  max: max <= 0 ? 1 : max,
                  onChanged: max <= 0
                      ? null
                      : (v) => services.handler.seek(Duration(milliseconds: v.round())),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_clock(position),
                          style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      Text(_clock(duration),
                          style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static String _clock(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

class _Controls extends StatelessWidget {
  const _Controls({required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return StreamBuilder<PlaybackState>(
      stream: services.handler.playbackState.stream,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final playing = state?.playing ?? false;
        final busy = state?.processingState == AudioProcessingState.loading ||
            state?.processingState == AudioProcessingState.buffering;
        final shuffle = state?.shuffleMode == AudioServiceShuffleMode.all;
        final repeat = state?.repeatMode ?? AudioServiceRepeatMode.none;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              tooltip: 'Shuffle',
              icon: Icon(Icons.shuffle, color: shuffle ? accent : Colors.white54),
              onPressed: services.handler.toggleShuffle,
            ),
            IconButton(
              iconSize: 34,
              icon: const Icon(Icons.skip_previous),
              onPressed: services.handler.skipToPrevious,
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(16),
              ),
              onPressed: busy
                  ? null
                  : () => playing ? services.handler.pause() : services.handler.play(),
              child: Icon(playing ? Icons.pause : Icons.play_arrow, size: 30),
            ),
            IconButton(
              iconSize: 34,
              icon: const Icon(Icons.skip_next),
              onPressed: services.handler.skipToNext,
            ),
            IconButton(
              tooltip: repeat == AudioServiceRepeatMode.one
                  ? 'Repeat one'
                  : repeat == AudioServiceRepeatMode.all
                      ? 'Repeat all'
                      : 'Repeat off',
              icon: Icon(
                repeat == AudioServiceRepeatMode.one ? Icons.repeat_one : Icons.repeat,
                color: repeat == AudioServiceRepeatMode.none ? Colors.white54 : accent,
              ),
              onPressed: services.handler.cycleRepeat,
            ),
          ],
        );
      },
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.services, required this.track});

  final AppServices services;
  final Track track;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: track.favorite ? 'Remove from liked' : 'Like',
          onPressed: services.handler.toggleFavorite,
          icon: Icon(
            track.favorite ? Icons.favorite : Icons.favorite_border,
            color: track.favorite ? Colors.redAccent : Colors.white70,
          ),
        ),
        TextButton.icon(
          onPressed: () => showAddToPlaylist(context, services, track),
          icon: const Icon(Icons.playlist_add, size: 18),
          label: const Text('Playlist'),
        ),
        ValueListenableBuilder<Set<String>>(
          valueListenable: services.cache.downloading,
          builder: (context, downloading, _) {
            final busy = downloading.contains(track.id);
            if (busy) {
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            return track.isCached
                ? TextButton.icon(
                    onPressed: () => services.cache.remove(track),
                    icon: const Icon(Icons.offline_pin, size: 18, color: Colors.greenAccent),
                    label: const Text('Saved'),
                  )
                : TextButton.icon(
                    onPressed: () => services.cache
                        .download(track, origin: 'manual', force: true)
                        .catchError((Object e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('$e')));
                      }
                      return null;
                    }),
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Download'),
                  );
          },
        ),
      ],
    );
  }
}

/// Explains the auto-cache decision in plain words, and lets you override it.
class _CacheRow extends StatelessWidget {
  const _CacheRow({required this.services, required this.track});

  final AppServices services;
  final Track track;

  @override
  Widget build(BuildContext context) {
    final needs = services.settings.autoCacheThreshold;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(track.isCached ? Icons.offline_pin : Icons.cloud_outlined,
              size: 18, color: track.isCached ? Colors.greenAccent : Colors.white38),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              track.isCached
                  ? (track.cacheOrigin == 'auto'
                      ? 'Saved automatically'
                      : 'Saved on this device')
                  : 'Played ${track.playCount}× · auto-saves after $needs plays '
                      'or one full listen',
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ),
          if (track.skipCount > 0)
            Text('${track.skipCount} early skips',
                style: const TextStyle(fontSize: 11, color: Colors.white38)),
        ],
      ),
    );
  }
}
