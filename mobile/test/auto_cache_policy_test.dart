import 'package:flutter_test/flutter_test.dart';

import 'package:aurora_music/data/auto_cache_policy.dart';
import 'package:aurora_music/data/models.dart';

Track track({
  String id = 'dQw4w9WgXcQ',
  int? duration = 200,
  int plays = 0,
  int skips = 0,
  bool favorite = false,
  String? audioPath,
}) =>
    Track(
      id: id,
      title: 'Instant Crush',
      artist: 'Daft Punk',
      duration: duration,
      playCount: plays,
      skipCount: skips,
      favorite: favorite,
      audioPath: audioPath,
    );

void main() {
  group('qualified play length', () {
    test('long tracks count after 30 seconds', () {
      expect(AutoCachePolicy.qualifiedAfter(track(duration: 400)),
          const Duration(seconds: 30));
    });

    test('short tracks count after half their length', () {
      expect(AutoCachePolicy.qualifiedAfter(track(duration: 20)),
          const Duration(seconds: 10));
    });

    test('unknown duration falls back to 30 seconds', () {
      expect(AutoCachePolicy.qualifiedAfter(track(duration: null)),
          const Duration(seconds: 30));
    });
  });

  group('long listen', () {
    test('one near-complete listen is enough, even with no repeats', () {
      const policy = AutoCachePolicy(threshold: 2);
      expect(policy.shouldCacheOnLongListen(track(plays: 0)), isTrue);
    });

    test('respects the auto-cache switch', () {
      const policy = AutoCachePolicy(enabled: false, threshold: 2);
      expect(policy.shouldCacheOnLongListen(track(plays: 0)), isFalse);
      expect(policy.shouldCacheOnLongListen(track(favorite: true)), isTrue);
    });

    test('never re-caches something already cached', () {
      const policy = AutoCachePolicy(threshold: 2);
      expect(policy.shouldCacheOnLongListen(track(audioPath: '/x.mp4')), isFalse);
    });

    test('long uploads still need a manual save', () {
      const policy = AutoCachePolicy(threshold: 2);
      expect(
        policy.shouldCacheOnLongListen(track(duration: 45 * 60)),
        isFalse,
      );
    });
  });

  group('auto cache decision', () {
    test('does nothing before the threshold', () {
      const policy = AutoCachePolicy(threshold: 2);
      expect(policy.shouldCache(track(plays: 1)), isFalse);
    });

    test('caches once the threshold is reached', () {
      const policy = AutoCachePolicy(threshold: 2);
      expect(policy.shouldCache(track(plays: 2)), isTrue);
    });

    test('early skips cancel plays out', () {
      const policy = AutoCachePolicy(threshold: 2);
      expect(policy.shouldCache(track(plays: 3, skips: 2)), isFalse);
      expect(policy.shouldCache(track(plays: 4, skips: 2)), isTrue);
    });

    test('already cached tracks are left alone', () {
      const policy = AutoCachePolicy(threshold: 2);
      expect(policy.shouldCache(track(plays: 9, audioPath: '/audio/x.m4a')), isFalse);
    });

    test('favourites are cached even when auto-cache is off', () {
      const policy = AutoCachePolicy(enabled: false, threshold: 2);
      expect(policy.shouldCache(track(plays: 0, favorite: true)), isTrue);
      expect(policy.shouldCache(track(plays: 9)), isFalse);
    });

    test('podcast-length uploads need a manual save', () {
      const policy = AutoCachePolicy(threshold: 2);
      expect(policy.shouldCache(track(plays: 5, duration: 45 * 60)), isFalse);
    });

    test('threshold is configurable', () {
      expect(const AutoCachePolicy(threshold: 3).shouldCache(track(plays: 2)), isFalse);
      expect(const AutoCachePolicy(threshold: 3).shouldCache(track(plays: 3)), isTrue);
    });
  });
}
