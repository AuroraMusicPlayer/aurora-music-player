import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../app_events.dart';
import '../data/auto_cache_policy.dart';
import '../data/device_cache.dart';
import '../data/library.dart';
import '../data/models.dart';
import '../data/youtube_source.dart';
import '../settings.dart';

/// Owns playback and the behaviour the app exists for:
///
///  1. a play only counts once playback passes [AutoCachePolicy.qualifiedAfter];
///  2. when a track's affinity reaches the threshold it is cached on device;
///  3. everything is resolved on this device — no server required.
class AuroraAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  AuroraAudioHandler({
    required this.source,
    required this.library,
    required this.cache,
    required this.settings,
    required this.events,
  }) {
    _player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object error, StackTrace stack) {
        this.error.value = '$error';
        _attemptRecovery();
      },
    );
    _player.currentIndexStream.listen(_onIndexChanged);
    _player.positionStream.listen(_onPosition);
  }

  final YouTubeSource source;
  final Library library;
  final DeviceCache cache;
  final Settings settings;
  final AppEvents events;

  AutoCachePolicy get policy => AutoCachePolicy(
        enabled: settings.autoCacheEnabled,
        threshold: settings.autoCacheThreshold,
      );

  final AudioPlayer _player = AudioPlayer();
  AudioSession? _session;

  final ValueNotifier<String?> error = ValueNotifier<String?>(null);
  final ValueNotifier<Track?> activeTrack = ValueNotifier<Track?>(null);

  /// Queue from the track the user started on, onwards.
  List<Track> _queue = [];
  int _appended = 0;
  int _generation = 0;
  int _recoveryAttempts = 0;

  AudioPlayer get player => _player;
  List<Track> get queueTracks => List.unmodifiable(_queue);

  /* ------------------------------- queue -------------------------------- */

  /// iOS only promotes an app to "Now Playing" (Control Center, Dynamic Island,
  /// lock screen) once it holds an active playback audio session.
  Future<void> _ensureSession() async {
    try {
      final session = _session ??= await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      await session.setActive(true);
    } catch (error) {
      if (kDebugMode) debugPrint('audio session setup failed: $error');
    }
  }

  Future<void> playTracks(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    await _ensureSession();
    final start = startIndex.clamp(0, tracks.length - 1);
    final generation = ++_generation;

    _queue = tracks.sublist(start);
    for (final track in _queue) {
      await library.remember(track);
    }

    _appended = 0;
    _queue[0] = await library.byId(_queue[0].id) ?? _queue[0];
    mediaItem.add(_mediaItem(_queue[0]));
    queue.add([_mediaItem(_queue[0])]);

    try {
      final first = await _audioSource(_queue.first);
      if (generation != _generation) return;

      _appended = 1;
      _recoveryAttempts = 0;
      await _player.setAudioSources([first]);
      await _player.play();
      unawaited(_appendRemaining(generation));
    } catch (exception) {
      if (generation != _generation) return;
      error.value = 'Could not play that track: $exception';
    }
  }

  /// Resolve and append the rest of the queue in the background, so playback
  /// starts immediately instead of waiting for 25 YouTube lookups.
  Future<void> _appendRemaining(int generation) async {
    while (_appended < _queue.length) {
      if (generation != _generation) return;
      final index = _appended;
      final track = _queue[index];
      try {
        final source = await _audioSource(track);
        if (generation != _generation) return;
        await _player.addAudioSource(source);
        _appended++;
        queue.add([for (final t in _queue.take(_appended)) _mediaItem(t)]);
      } catch (_) {
        if (generation != _generation) return;
        // An unplayable track shouldn't stall the queue behind it.
        _queue.removeAt(index);
      }
    }
  }

  Future<AudioSource> _audioSource(Track track) async {
    if (track.isCached && track.audioPath != null) {
      return AudioSource.uri(Uri.file(track.audioPath!), tag: _mediaItem(track));
    }
    final resolved = await source.stream(track.id);
    return AudioSource.uri(Uri.parse(resolved.url), tag: _mediaItem(track));
  }

  /* ----------------------------- transport ------------------------------ */

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  /// Off → all → one → off, the usual three-state repeat button.
  Future<void> cycleRepeat() async {
    final next = switch (_player.loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await _player.setLoopMode(next);
  }

  Future<void> toggleShuffle() async {
    await _player.setShuffleModeEnabled(!_player.shuffleModeEnabled);
  }

  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) await _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
    } else if (_player.hasPrevious) {
      await _player.seekToPrevious();
    } else {
      await _player.seek(Duration.zero);
    }
  }

  /* ------------------------- play accounting ---------------------------- */

  Track? _active;
  bool _activeCounted = false;
  bool _activeStarted = false;
  bool _longListenHandled = false;

  void _onIndexChanged(int? index) {
    final previous = _active;
    if (previous != null && !_activeCounted && _activeStarted) {
      library.recordSkip(previous.id).then((_) => events.bump());
    }

    _activeCounted = false;
    _activeStarted = false;
    _longListenHandled = false;

    if (index == null || index < 0 || index >= _queue.length) {
      _active = null;
      activeTrack.value = null;
      return;
    }

    _active = _queue[index];
    activeTrack.value = _active;
    mediaItem.add(_mediaItem(_active!));
    _refreshActive();
  }

  void _onPosition(Duration position) {
    final track = _active;
    if (track == null) return;

    if (!_activeStarted && position > const Duration(seconds: 1)) {
      _activeStarted = true;
    }
    // "Played right through" is a stronger signal than "tapped twice".
    if (!_longListenHandled && track.duration != null && track.duration! > 0) {
      final fraction = position.inSeconds / track.duration!;
      if (fraction >= 0.8) {
        _longListenHandled = true;
        _maybeAutoCache(track, longListen: true);
      }
    }

    if (_activeCounted || !_activeStarted) return;
    if (position < AutoCachePolicy.qualifiedAfter(track)) return;

    _activeCounted = true;
    _countQualifiedPlay(track);
  }

  Future<void> _countQualifiedPlay(Track track) async {
    await library.recordPlay(track.id);
    events.bump();
    await _refreshActive();
    await _maybeAutoCache(track);
  }

  Future<void> _refreshActive() async {
    final track = _active;
    if (track == null) return;
    final fresh = await library.byId(track.id);
    if (fresh == null) return;
    final index = _queue.indexWhere((t) => t.id == track.id);
    if (index != -1) _queue[index] = fresh;
    if (_active?.id == fresh.id) {
      _active = fresh;
      activeTrack.value = fresh;
      mediaItem.add(_mediaItem(fresh));
    }
  }

  /// This is the feature: repeated listening earns an offline copy.
  Future<void> _maybeAutoCache(Track track, {bool longListen = false}) async {
    final fresh = await library.byId(track.id) ?? track;
    final wanted =
        longListen ? policy.shouldCacheOnLongListen(fresh) : policy.shouldCache(fresh);
    if (!wanted) return;

    unawaited(
      cache.download(fresh, origin: fresh.favorite ? 'manual' : 'auto').then((updated) {
        if (updated != null) {
          _replaceInQueue(updated);
          events.bump();
        }
      }).catchError((Object e) {
        if (kDebugMode) debugPrint('auto-cache failed for ${fresh.id}: $e');
      }),
    );
  }

  void _replaceInQueue(Track track) {
    final index = _queue.indexWhere((t) => t.id == track.id);
    if (index == -1) return;
    _queue[index] = track;
    if (_active?.id == track.id) {
      _active = track;
      activeTrack.value = track;
    }
  }

  /// Signed googlevideo URLs expire after a few hours. If playback dies,
  /// re-resolve the current track once and resume where it stopped.
  Future<void> _attemptRecovery() async {
    if (_recoveryAttempts >= 2) return;
    final index = _player.currentIndex;
    if (index == null || index >= _queue.length) return;

    final track = _queue[index];
    if (track.isCached) return; // a broken file is not a URL problem

    _recoveryAttempts++;
    final position = _player.position;
    source.invalidate(track.id);
    await playTracks(_queue, startIndex: index);
    if (position > const Duration(seconds: 2)) {
      await _player.seek(position);
    }
  }

  /* --------------------------- audio_service ---------------------------- */

  MediaItem _mediaItem(Track track) => MediaItem(
        id: track.id,
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: track.length,
        artUri: track.thumbnail == null ? null : Uri.tryParse(track.thumbnail!),
        extras: {'cached': track.isCached},
      );

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: _mapState(_player.processingState),
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _player.currentIndex,
      repeatMode: switch (_player.loopMode) {
        LoopMode.one => AudioServiceRepeatMode.one,
        LoopMode.all => AudioServiceRepeatMode.all,
        LoopMode.off => AudioServiceRepeatMode.none,
      },
      shuffleMode: _player.shuffleModeEnabled
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
    ));
  }

  static AudioProcessingState _mapState(ProcessingState state) => switch (state) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      };

  Future<void> disposeHandler() async {
    await _player.dispose();
    error.dispose();
    activeTrack.dispose();
  }
}
