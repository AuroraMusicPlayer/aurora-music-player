import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../app_events.dart';
import '../data/artwork_cache.dart';
import '../data/auto_cache_policy.dart';
import '../data/device_cache.dart';
import '../data/library.dart';
import '../data/home_widget.dart';
import '../data/live_activity.dart';
import '../data/models.dart';
import '../data/music_filter.dart';
import '../data/playback_memory.dart';
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
    this.memory,
    this.artwork,
  }) {
    _player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object error, StackTrace stack) {
        this.error.value = _translatePlaybackError(error);
        _attemptRecovery();
      },
    );
    _player.currentIndexStream.listen(_onIndexChanged);
    _player.positionStream.listen(_onPosition);
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _onQueueFinished();
    });
  }

  final YouTubeSource source;
  final Library library;
  final DeviceCache cache;
  final Settings settings;
  final AppEvents events;
  final PlaybackMemory? memory;
  final ArtworkCache? artwork;

  DateTime _lastSavedAt = DateTime.fromMillisecondsSinceEpoch(0);

  AutoCachePolicy get policy => AutoCachePolicy(
        enabled: settings.autoCacheEnabled,
        threshold: settings.autoCacheThreshold,
      );

  final AudioPlayer _player = AudioPlayer();
  AudioSession? _session;

  final ValueNotifier<String?> error = ValueNotifier<String?>(null);
  final ValueNotifier<Track?> activeTrack = ValueNotifier<Track?>(null);

  /// When the sleep timer will pause playback, or null when it is off.
  final ValueNotifier<DateTime?> sleepEndsAt = ValueNotifier<DateTime?>(null);
  final ValueNotifier<double> speed = ValueNotifier<double>(1.0);
  final ValueNotifier<bool> autoplayEnabled = ValueNotifier<bool>(true);

  Timer? _sleepTimer;
  Timer? _fadeTimer;

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
  /// When the queue runs out and autoplay is on, continue with a search seeded
  /// by the last artist so music never stops unexpectedly.
  Future<void> _onQueueFinished() async {
    if (!autoplayEnabled.value) return;
    final last = _active;
    if (last == null) return;

    try {
      final more = await source.search('${last.artist} mix', limit: 12);
      final fresh = MusicFilter.songsOnly(more)
          .where((t) => !_queue.any((q) => q.id == t.id))
          .take(5)
          .toList(growable: false);
      if (fresh.isEmpty) return;

      for (final track in fresh) {
        await library.remember(track);
        _queue.add(track);
        await _player.addAudioSource(await _audioSource(track));
        _appended++;
      }
      queue.add([for (final t in _queue) _mediaItem(t)]);
      await _player.seek(Duration.zero, index: _queue.length - fresh.length);
      await _player.play();
    } catch (_) {
      // Autoplay is a nicety; never surface it as an error.
    }
  }

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
      // A cache entry written by an older build may be a DASH fragment that the
      // system decoder refuses. Drop it rather than fail playback.
      if (await cache.isPlayableFile(track.audioPath!)) {
        return AudioSource.uri(Uri.file(track.audioPath!), tag: _mediaItem(track));
      }
      await cache.remove(track);
      final cleared = track.withoutCache();
      final index = _queue.indexWhere((t) => t.id == track.id);
      if (index != -1) _queue[index] = cleared;
      if (_active?.id == track.id) {
        _active = cleared;
        activeTrack.value = cleared;
      }
    }
    final resolved = await source.stream(track.id);
    return AudioSource.uri(Uri.parse(resolved.url), tag: _mediaItem(track));
  }

  /* ----------------------------- transport ------------------------------ */

  @override
  Future<void> play() async {
    await _player.play();
    unawaited(LiveActivity.sync(isPlaying: true, track: _active));
    unawaited(_syncHomeWidget());
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    unawaited(LiveActivity.sync(isPlaying: false, track: _active));
    unawaited(_syncHomeWidget());
    final track = _active;
    if (track != null) {
      unawaited(memory?.save(track, _player.position) ?? Future<void>.value());
    }
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  /// Closes playback entirely, the way the X on the YouTube mini player does.
  Future<void> dismiss() async {
    _generation++;
    await _player.stop();
    await _player.setAudioSources([]);
    _queue.clear();
    _appended = 0;
    _active = null;
    activeTrack.value = null;
    mediaItem.add(null);
    queue.add([]);
    unawaited(LiveActivity.end());
    unawaited(HomeWidget.clear());
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  /* ---------------------------- queue editing --------------------------- */

  /// Rebuilds the player playlist from [_queue], keeping the current track and
  /// position. Used by reorder / remove / play-next, none of which just_audio
  /// supports in place.
  Future<void> _rebuild({required int index, Duration position = Duration.zero, bool resume = true}) async {
    final sources = <AudioSource>[];
    for (final track in _queue) {
      sources.add(await _audioSource(track));
    }
    _appended = _queue.length;
    queue.add([for (final track in _queue) _mediaItem(track)]);
    await _player.setAudioSources(
      sources,
      initialIndex: index.clamp(0, sources.isEmpty ? 0 : sources.length - 1),
      initialPosition: position,
    );
    if (resume && _player.playing) unawaited(_player.play());
  }

  Future<void> jumpTo(int index) async {
    if (index < 0 || index >= _queue.length) return;
    await _player.seek(Duration.zero, index: index);
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final playingIndex = _player.currentIndex ?? 0;
    final position = _player.position;
    final wasPlaying = _player.playing;

    _queue.removeAt(index);

    if (_queue.isEmpty) {
      await _player.stop();
      mediaItem.add(null);
      activeTrack.value = null;
      return;
    }

    final nextIndex = index < playingIndex
        ? playingIndex - 1
        : (index == playingIndex ? playingIndex : playingIndex);
    await _rebuild(
      index: nextIndex.clamp(0, _queue.length - 1),
      position: index == playingIndex ? Duration.zero : position,
      resume: wasPlaying,
    );
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex == oldIndex) return;

    final playing = _active;
    final position = _player.position;
    final wasPlaying = _player.playing;

    final track = _queue.removeAt(oldIndex);
    _queue.insert(newIndex.clamp(0, _queue.length), track);

    final index = playing == null ? 0 : _queue.indexWhere((t) => t.id == playing.id);
    await _rebuild(
      index: index < 0 ? 0 : index,
      position: position,
      resume: wasPlaying,
    );
  }

  /// Plays the tapped song, then an algorithmically related queue rather than
  /// the rest of the search list in YouTube's order.
  ///
  /// The related part is shuffled up front instead of enabling just_audio's
  /// shuffle, which would also reorder the seed and could start elsewhere.
  Future<void> startQueueFromTrack(Track seed, {List<Track> fallback = const []}) async {
    final results = await source.search('${seed.artist} ${seed.title} mix', limit: 20);
    final related = MusicFilter.songsOnly(results)
        .where((t) => t.id != seed.id)
        .toList(growable: true)
      ..shuffle();

    final queue = <Track>[seed, ...related.take(20)];
    if (queue.length < 4) {
      // Not enough related material: fall back to the search results, still
      // filtered, so the queue is never two songs long.
      queue.addAll(
        MusicFilter.songsOnly(fallback).where((t) => t.id != seed.id).take(15),
      );
    }
    await playTracks(queue);
  }

  /// Spoken queries from the car ("play Noizy") arrive here.
  @override
  Future<void> playFromSearch(String query, [Map<String, dynamic>? extras]) async {
    final results = await source.search(query, limit: 10);
    if (results.isEmpty) return;
    await startQueueFromTrack(results.first, fallback: results);
  }

  /// Endless-ish radio seeded by a track: the seed first, then a search mix
  /// built around its artist. Autoplay keeps it going afterwards.
  Future<void> startRadio(Track seed, {int size = 15}) async {
    final results = await source.search('${seed.artist} radio', limit: size);
    final related = MusicFilter.songsOnly(
      results.where((t) => t.id != seed.id).toList(growable: false),
    ).toList()
      ..shuffle();

    final tracks = <Track>[
      seed,
      ...related,
    ];
    if (tracks.length == 1) {
      // Nothing similar found; at least play the seed.
      await playTracks([seed]);
      return;
    }
    await playTracks(tracks);
  }

  /// Insert directly after the current track.
  Future<void> playNext(Track track) async {
    if (_queue.isEmpty) {
      await playTracks([track]);
      return;
    }
    await library.remember(track);
    final current = _player.currentIndex ?? 0;
    final position = _player.position;
    final wasPlaying = _player.playing;

    _queue.insert((current + 1).clamp(0, _queue.length), track);
    await _rebuild(index: current, position: position, resume: wasPlaying);
  }

  Future<void> addToQueue(Track track) async {
    if (_queue.isEmpty) {
      await playTracks([track]);
      return;
    }
    await library.remember(track);
    _queue.add(track);
    await _player.addAudioSource(await _audioSource(track));
    _appended = _queue.length;
    queue.add([for (final t in _queue) _mediaItem(t)]);
  }

  /* ------------------------- speed & sleep timer ------------------------ */

  Future<void> cycleSpeed() async {
    const speeds = [1.0, 1.25, 1.5, 2.0, 0.75, 0.5];
    final current = speed.value;
    final index = speeds.indexOf(current);
    final next = speeds[(index + 1) % speeds.length];
    await _player.setSpeed(next);
    speed.value = next;
  }

  /// Pauses playback after [duration], fading the volume out over the last
  /// ten seconds so it does not cut off abruptly. Null cancels.
  void setSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    _fadeTimer?.cancel();

    if (duration == null) {
      sleepEndsAt.value = null;
      _player.setVolume(1);
      return;
    }

    sleepEndsAt.value = DateTime.now().add(duration);
    final fadeStart = duration - const Duration(seconds: 10);

    if (fadeStart <= Duration.zero) {
      _sleepTimer = Timer(duration, _finishSleep);
      return;
    }

    _sleepTimer = Timer(fadeStart, () {
      var step = 0;
      _fadeTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
        step++;
        _player.setVolume((1 - step / 20).clamp(0.0, 1.0));
        if (step >= 20) {
          timer.cancel();
          _finishSleep();
        }
      });
    });
  }

  Future<void> _finishSleep() async {
    await _player.pause();
    await _player.setVolume(1);
    sleepEndsAt.value = null;
  }

  /// Heart / un-heart the current track. Favourites are also cached, because
  /// liking something is the clearest possible signal that it should be
  /// available offline.
  Future<void> toggleFavorite() async {
    final track = _active;
    if (track == null) return;

    final next = !track.favorite;
    await library.setFavorite(track.id, next);
    events.bump();
    await _refreshActive();

    if (next) {
      final fresh = await library.byId(track.id);
      if (fresh != null) {
        unawaited(
          cache.download(fresh, origin: 'manual').then((updated) {
            if (updated != null) {
              _replaceInQueue(updated);
              events.bump();
            }
          }).catchError((Object _) {}),
        );
      }
    }
  }

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
    unawaited(_localizeArtwork(_active!));
    unawaited(LiveActivity.sync(isPlaying: _player.playing, track: _active));
    unawaited(_syncHomeWidget());
    _refreshActive();
  }

  void _onPosition(Duration position) {
    final track = _active;
    if (track == null) return;

    // Persist roughly every ten seconds so a relaunch can resume. Written on
    // the position stream rather than a timer so it stops when playback stops.
    final now = DateTime.now();
    if (now.difference(_lastSavedAt) > const Duration(seconds: 10)) {
      _lastSavedAt = now;
      unawaited(memory?.save(track, position) ?? Future<void>.value());
    }

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

  Future<void> _syncHomeWidget() async {
    final track = _active;
    final path = track == null ? null : await artwork?.pathFor(track.id);
    await HomeWidget.sync(
      track: track,
      isPlaying: _player.playing,
      artworkPath: path,
    );
  }

  /// Re-publishes the media item with artwork cached on disk. The system asks
  /// for artwork lazily; a local file answers instantly where a remote URL
  /// often arrives too late.
  Future<void> _localizeArtwork(Track track) async {
    final cache = artwork;
    if (cache == null || track.thumbnail == null) return;
    final uri = await cache.forTrack(track.id, track.thumbnail);
    if (uri == null || _active?.id != track.id) return;
    mediaItem.add(_mediaItem(track, artUri: uri));
    unawaited(_syncHomeWidget());
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
    _recoveryAttempts++;
    final position = _player.position;

    // A cached file that fails to decode is worse than no cache: remove it and
    // come back from the network.
    if (track.isCached && track.audioPath != null) {
      if (!await cache.isPlayableFile(track.audioPath!)) {
        await cache.remove(track);
        _queue[index] = track.withoutCache();
      }
    }
    source.invalidate(track.id);
    await playTracks(_queue, startIndex: index);
    if (position > const Duration(seconds: 2)) {
      await _player.seek(position);
    }
  }

  /// AVPlayer reports almost everything as -11800 "unknown error"; the useful
  /// detail is nested inside. Turning that into a sentence is the difference
  /// between "something broke" and knowing what to do.
  static String _translatePlaybackError(Object error) {
    final text = error.toString();

    if (text.contains('403') || text.contains('-12660')) {
      return 'YouTube refused this stream (403). That is usually rate limiting — '
          'wait a few minutes, or play something already saved offline.';
    }
    if (text.contains('-11800')) {
      return 'The system could not decode this track. If it was saved earlier, '
          'tap Download again to refresh the file; otherwise try another song.';
    }
    if (text.contains('Source error') || text.contains('404')) {
      return 'That stream is no longer available. Try playing it again.';
    }
    return 'Could not play that track: $text';
  }

  /* ---------------------- Android Auto / car browsing -------------------- */

  static const browseRoot = 'aurora_root';
  static const browseLibrary = 'library';
  static const browsePlaylists = 'playlists';
  static const browseLiked = 'liked';
  static const browseOffline = 'offline';
  static const browseRecent = 'recent';
  static const browseRotation = 'rotation';
  static const browseShuffle = 'shuffle_all';
  static const _playlistPrefix = 'playlist:';

  /// Content-style hints. Without these the head unit guesses, and a shelf of
  /// songs can render as big tiles instead of a list.
  static const _listStyle = <String, dynamic>{
    'android.media.browse.CONTENT_STYLE_BROWSABLE_HINT': 1, // LIST
    'android.media.browse.CONTENT_STYLE_PLAYABLE_HINT': 1, // LIST
  };

  /// The tree a head unit browses: two folders plus the shortcuts people use
  /// while driving.
  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    // audio_service's root id differs between versions; anything that is not a
    // known node is treated as the root.
    const nodes = {
      browseLibrary,
      browsePlaylists,
      browseLiked,
      browseOffline,
      browseRecent,
      browseRotation,
      browseShuffle,
    };
    final isKnown = nodes.contains(parentMediaId) ||
        parentMediaId.startsWith(_playlistPrefix);

    if (!isKnown) {
      return [
        MediaItem(
          id: browseLibrary,
          title: 'Your library',
          playable: false,
          extras: _listStyle,
        ),
        MediaItem(
          id: browsePlaylists,
          title: 'Playlists',
          playable: false,
          extras: _listStyle,
        ),
        MediaItem(
          id: browseRecent,
          title: 'Recently played',
          playable: false,
          extras: _listStyle,
        ),
        MediaItem(
          id: browseShuffle,
          title: 'Shuffle everything',
          playable: true,
        ),
      ];
    }

    if (parentMediaId == browseLibrary) {
      return [
        MediaItem(id: browseLiked, title: 'Liked songs', playable: false, extras: _listStyle),
        MediaItem(id: browseOffline, title: 'Offline songs', playable: false, extras: _listStyle),
        MediaItem(id: browseRecent, title: 'Recently played', playable: false, extras: _listStyle),
        MediaItem(id: browseRotation, title: 'Heavy rotation', playable: false, extras: _listStyle),
      ];
    }

    if (parentMediaId == browsePlaylists) {
      final playlists = await library.playlists();
      return [
        for (final playlist in playlists)
          MediaItem(
            id: '$_playlistPrefix${playlist.id}',
            title: playlist.name,
            playable: false,
            artUri: playlist.thumbnail == null
                ? null
                : Uri.tryParse(playlist.thumbnail!),
            extras: _listStyle,
          ),
      ];
    }

    final tracks = await _tracksFor(parentMediaId);
    return [
      for (final track in tracks)
        _mediaItem(track, parent: parentMediaId),
    ];
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    final track = await library.byId(mediaId);
    return track == null ? null : _mediaItem(track);
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    // "Shuffle everything" is an action, not a track.
    if (mediaId == browseShuffle) {
      final favourites = await library.favorites(limit: 100);
      final pool = favourites.isNotEmpty
          ? favourites
          : await library.mostPlayed(limit: 100);
      if (pool.isEmpty) return;
      if (!_player.shuffleModeEnabled) {
        await _player.setShuffleModeEnabled(true);
      }
      await playTracks(pool..shuffle());
      return;
    }

    final parent = extras?['parent'] as String? ?? browseRecent;
    final tracks = await _tracksFor(parent);
    if (tracks.isEmpty) return;

    final index = tracks.indexWhere((t) => t.id == mediaId);
    await playTracks(tracks, startIndex: index < 0 ? 0 : index);
  }

  Future<List<Track>> _tracksFor(String parent) async {
    if (parent.startsWith(_playlistPrefix)) {
      final id = int.tryParse(parent.substring(_playlistPrefix.length));
      if (id == null) return const [];
      return library.playlistTracks(id);
    }
    return switch (parent) {
      browseLiked => library.favorites(),
      browseOffline => library.offline(origin: 'auto'),
      browseRotation => library.mostPlayed(),
      _ => library.recent(),
    };
  }

  /* --------------------------- audio_service ---------------------------- */

  MediaItem _mediaItem(Track track, {String? parent, Uri? artUri}) => MediaItem(
        id: track.id,
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: track.length,
        artUri: artUri ??
            (track.thumbnail == null ? null : Uri.tryParse(track.thumbnail!)),
        extras: {
          'cached': track.isCached,
          if (parent != null) 'parent': parent,
        },
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
