import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';
import 'lyrics_sheet.dart';
import 'playlist_dialogs.dart';
import 'queue_sheet.dart';

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
              const SizedBox(height: 4),
              _Tools(services: services, track: track),
              const SizedBox(height: 8),
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

/// Lyrics, queue, speed and sleep timer.
class _Tools extends StatelessWidget {
  const _Tools({required this.services, required this.track});

  final AppServices services;
  final Track track;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ToolButton(
          icon: Icons.lyrics_outlined,
          label: 'Lyrics',
          onTap: () => showLyricsSheet(context, services, track),
        ),
        _ToolButton(
          icon: Icons.queue_music,
          label: 'Queue',
          onTap: () => showQueueSheet(context, services),
        ),
        ValueListenableBuilder<double>(
          valueListenable: services.handler.speed,
          builder: (context, speed, _) => _ToolButton(
            icon: Icons.speed,
            label: speed == 1 ? 'Speed' : '${speed}x',
            onTap: services.handler.cycleSpeed,
          ),
        ),
        ValueListenableBuilder<DateTime?>(
          valueListenable: services.handler.sleepEndsAt,
          builder: (context, endsAt, _) {
            final label = endsAt == null
                ? 'Sleep'
                : '${endsAt.difference(DateTime.now()).inMinutes + 1}m';
            return _ToolButton(
              icon: endsAt == null ? Icons.bedtime_outlined : Icons.bedtime,
              label: label,
              onTap: () => _showSleepTimer(context, services),
            );
          },
        ),
      ],
    );
  }

  void _showSleepTimer(BuildContext context, AppServices services) {
    final handler = services.handler;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF141414),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Sleep timer',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
            for (final minutes in [15, 30, 45, 60])
              ListTile(
                title: Text('$minutes minutes'),
                onTap: () {
                  handler.setSleepTimer(Duration(minutes: minutes));
                  Navigator.pop(sheetContext);
                },
              ),
            ListTile(
              leading: const Icon(Icons.timer_off_outlined),
              title: const Text('Off'),
              onTap: () {
                handler.setSleepTimer(null);
                Navigator.pop(sheetContext);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: Colors.white70),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(fontSize: 10, color: Colors.white54)),
          ],
        ),
      ),
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
