import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';

Future<void> showPlayerSheet(BuildContext context, AppServices services) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
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
                borderRadius: BorderRadius.circular(24),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: track.thumbnail == null
                      ? const ColoredBox(color: Colors.white12)
                      : Image.network(track.thumbnail!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                track.title,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              _PositionBar(services: services),
              const SizedBox(height: 8),
              _Controls(services: services),
              const SizedBox(height: 20),
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
                      Text(_clock(position), style: Theme.of(context).textTheme.bodySmall),
                      Text(_clock(duration), style: Theme.of(context).textTheme.bodySmall),
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
    return StreamBuilder<PlaybackState>(
      stream: services.handler.playbackState.stream,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final playing = state?.playing ?? false;
        final busy = state?.processingState == AudioProcessingState.loading ||
            state?.processingState == AudioProcessingState.buffering;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: 36,
              icon: const Icon(Icons.skip_previous),
              onPressed: services.handler.skipToPrevious,
            ),
            const SizedBox(width: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(18),
              ),
              onPressed: busy
                  ? null
                  : () => playing ? services.handler.pause() : services.handler.play(),
              child: Icon(playing ? Icons.pause : Icons.play_arrow, size: 32),
            ),
            const SizedBox(width: 16),
            IconButton(
              iconSize: 36,
              icon: const Icon(Icons.skip_next),
              onPressed: services.handler.skipToNext,
            ),
          ],
        );
      },
    );
  }
}

/// Shows the listening stats the auto-cache decision is based on, and lets you
/// override the decision in either direction.
class _CacheRow extends StatelessWidget {
  const _CacheRow({required this.services, required this.track});

  final AppServices services;
  final Track track;

  @override
  Widget build(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    final needs = services.settings.autoCacheThreshold;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(track.isCached ? Icons.offline_pin : Icons.cloud_outlined,
                  color: track.isCached ? Colors.greenAccent : null),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  track.isCached
                      ? (track.cacheOrigin == 'auto'
                          ? 'Saved automatically after $needs plays'
                          : 'Saved on this device')
                      : 'Played ${track.playCount}× · saved after $needs plays',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (track.isCached)
                TextButton(
                  onPressed: () async {
                    await services.cache.remove(track);
                    messenger.showSnackBar(
                        const SnackBar(content: Text('Removed from this device')));
                  },
                  child: const Text('Remove'),
                )
              else
                TextButton(
                  onPressed: () async {
                    try {
                      await services.cache.download(track, origin: 'manual', force: true);
                      messenger.showSnackBar(const SnackBar(content: Text('Saved for offline')));
                    } catch (error) {
                      messenger.showSnackBar(SnackBar(content: Text('Failed: $error')));
                    }
                  },
                  child: const Text('Save now'),
                ),
            ],
          ),
          if (!track.isCached && track.skipCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(Icons.fast_forward, size: 16),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Skipped early ${track.skipCount}× — skips cancel out plays',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
