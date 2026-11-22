import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';
import 'artwork.dart';
import 'lyrics_sheet.dart';
import 'playlist_dialogs.dart';
import 'queue_sheet.dart';

/// Opens the full player. Slides up over the tabs, and the artwork grows out
/// of the mini player.
Future<void> showPlayerSheet(BuildContext context, AppServices services) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 340),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => PlayerScreen(services: services),
      transitionsBuilder: (_, animation, __, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero)
              .animate(curved),
          child: child,
        );
      },
    ),
  );
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  @override
  void initState() {
    super.initState();
    widget.services.handler.error.addListener(_showError);
  }

  @override
  void dispose() {
    widget.services.handler.error.removeListener(_showError);
    super.dispose();
  }

  /// Playback failures were only surfaced by the tab shell, so a failure while
  /// the player was open looked like a frozen track.
  void _showError() {
    final message = widget.services.handler.error.value;
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    return Scaffold(
      backgroundColor: const Color(0xFF070707),
      body: ValueListenableBuilder<Track?>(
        valueListenable: services.handler.activeTrack,
        builder: (context, track, _) {
          if (track == null) {
            return const Center(child: Text('Nothing playing'));
          }
          return _PlayerBody(services: services, track: track);
        },
      ),
    );
  }
}

class _PlayerBody extends StatefulWidget {
  const _PlayerBody({required this.services, required this.track});

  final AppServices services;
  final Track track;

  @override
  State<_PlayerBody> createState() => _PlayerBodyState();
}

class _PlayerBodyState extends State<_PlayerBody> {
  double _drag = 0;

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    final track = widget.track;

    return GestureDetector(
      // Measure the drag rather than only the release velocity: a slow, long
      // swipe down should close the player too.
      onVerticalDragStart: (_) => _drag = 0,
      onVerticalDragUpdate: (details) {
        _drag += details.delta.dy;
        if (_drag > 90) {
          _drag = 0;
          Navigator.of(context).maybePop();
        }
      },
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        _drag = 0;
        if (velocity > 500) Navigator.of(context).maybePop();
      },
      child: Stack(
        children: [
          _Backdrop(track: track),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Column(
                children: [
                  _PlayerHeader(onClose: () => Navigator.of(context).maybePop()),
                  const SizedBox(height: 12),
                  Hero(
                    tag: 'now-playing-art',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: artworkForVideo(track.id),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    track.title,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, color: Colors.white60),
                  ),
                  const SizedBox(height: 22),
                  _PositionBar(services: services, track: track),
                  const SizedBox(height: 6),
                  _Controls(services: services),
                  const SizedBox(height: 10),
                  _Tools(services: services, track: track),
                  const SizedBox(height: 14),
                  _Actions(services: services, track: track),
                  const SizedBox(height: 16),
                  _CacheRow(services: services, track: track),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Blurred, darkened artwork behind everything.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          artworkForVideo(track.id,
              placeholderColor: const Color(0xFF101010)),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
            child: const ColoredBox(color: Color(0xCC000000)),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xE6000000)],
                stops: [0.35, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Down-arrow to collapse the player, plus the grab handle.
class _PlayerHeader extends StatelessWidget {
  const _PlayerHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Hide player',
          onPressed: onClose,
          icon: const Icon(Icons.keyboard_arrow_down, size: 28),
        ),
        const Expanded(
          child: Center(
            child: SizedBox(
              width: 36,
              height: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 48),
      ],
    );
  }
}

class _PositionBar extends StatelessWidget {
  const _PositionBar({required this.services, required this.track});

  final AppServices services;
  final Track track;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return StreamBuilder<Duration>(
      stream: services.handler.player.positionStream,
      builder: (context, positionSnapshot) {
        return StreamBuilder<Duration?>(
          stream: services.handler.player.durationStream,
          builder: (context, durationSnapshot) {
            // Until the stream reports its length, the catalogue metadata is a
            // better answer than zero.
            final duration = durationSnapshot.data ?? track.length ?? Duration.zero;
            final position = positionSnapshot.data ?? Duration.zero;
            final max = duration.inMilliseconds.toDouble();
            final value =
                position.inMilliseconds.toDouble().clamp(0, max <= 0 ? 1 : max);

            return Column(
              children: [
                SizedBox(
                  height: 28,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: accent,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: max <= 0 ? 0 : value.toDouble(),
                      max: max <= 0 ? 1 : max,
                      onChanged: max <= 0
                          ? null
                          : (v) =>
                              services.handler.seek(Duration(milliseconds: v.round())),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_clock(position),
                          style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              fontFeatures: [FontFeature.tabularFigures()])),
                      Text(_clock(duration),
                          style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              fontFeatures: [FontFeature.tabularFigures()])),
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              tooltip: 'Shuffle',
              iconSize: 22,
              icon: Icon(Icons.shuffle, color: shuffle ? accent : Colors.white54),
              onPressed: services.handler.toggleShuffle,
            ),
            IconButton(
              iconSize: 36,
              icon: const Icon(Icons.skip_previous),
              onPressed: services.handler.skipToPrevious,
            ),
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                iconSize: 36,
                color: Colors.black,
                padding: const EdgeInsets.all(12),
                onPressed: busy
                    ? null
                    : () => playing
                        ? services.handler.pause()
                        : services.handler.play(),
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              ),
            ),
            IconButton(
              iconSize: 36,
              icon: const Icon(Icons.skip_next),
              onPressed: services.handler.skipToNext,
            ),
            IconButton(
              tooltip: repeat == AudioServiceRepeatMode.one
                  ? 'Repeat one'
                  : repeat == AudioServiceRepeatMode.all
                      ? 'Repeat all'
                      : 'Repeat off',
              iconSize: 22,
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
          icon: Icons.radio,
          label: 'Radio',
          onTap: () => services.handler.startRadio(track),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
        ValueListenableBuilder<Map<String, double>>(
          valueListenable: services.cache.progress,
          builder: (context, progressMap, _) =>
              ValueListenableBuilder<Set<String>>(
            valueListenable: services.cache.downloading,
            builder: (context, downloading, _) {
              if (downloading.contains(track.id)) {
                final pct = progressMap[track.id];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(pct == null ? '…' : '${(pct * 100).round()}%',
                      style: const TextStyle(color: Colors.white54)),
                );
              }
              return track.isCached
                  ? TextButton.icon(
                      onPressed: () => services.cache.remove(track),
                      icon: const Icon(Icons.offline_pin,
                          size: 18, color: Colors.greenAccent),
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
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
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
