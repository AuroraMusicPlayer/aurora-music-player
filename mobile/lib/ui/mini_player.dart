import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import 'player_sheet.dart';
import 'widgets.dart';

/// Persistent bar above the navigation, with a live progress line.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: services.handler.mediaItem.stream,
      builder: (context, snapshot) {
        final item = snapshot.data;
        if (item == null) return const SizedBox.shrink();

        return StreamBuilder<PlaybackState>(
          stream: services.handler.playbackState.stream,
          builder: (context, playbackSnapshot) {
            final playing = playbackSnapshot.data?.playing ?? false;

            return Material(
              color: const Color(0xFF141414),
              child: InkWell(
                onTap: () => showPlayerSheet(context, services),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StreamBuilder<Duration>(
                      stream: services.handler.player.positionStream,
                      builder: (context, positionSnapshot) {
                        return StreamBuilder<Duration?>(
                          stream: services.handler.player.durationStream,
                          builder: (context, durationSnapshot) {
                            return NowPlayingBar(
                              position: positionSnapshot.data ?? Duration.zero,
                              duration: durationSnapshot.data ?? Duration.zero,
                            );
                          },
                        );
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                      child: Row(
                        children: [
                          Hero(
                            tag: 'now-playing-art',
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 46,
                                height: 46,
                                child: item.artUri == null
                                    ? const ColoredBox(color: Color(0xFF2A2A2A))
                                    : Image.network(item.artUri.toString(),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const ColoredBox(
                                            color: Color(0xFF2A2A2A))),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w500)),
                                Text(item.artist ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 12)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                            onPressed: () =>
                                playing ? services.handler.pause() : services.handler.play(),
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next),
                            onPressed: services.handler.skipToNext,
                          ),
                          IconButton(
                            tooltip: 'Close player',
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: services.handler.dismiss,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
