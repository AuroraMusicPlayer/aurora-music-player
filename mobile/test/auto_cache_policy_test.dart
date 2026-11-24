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

  group('listen-through point', () {
    test('defaults to 80% of the track', () {
      const policy = AutoCachePolicy();
      expect(policy.percent, 80);
      expect(policy.cachePoint(track(duration: 200)),
          const Duration(seconds: 160));
    });

    test('is configurable', () {
      const policy = AutoCachePolicy(percent: 75);
      expect(policy.cachePoint(track(duration: 200)),
          const Duration(seconds: 150));
    });

    test('stays inside 50–100%', () {
      expect(const AutoCachePolicy(percent: 10).fraction, 0.5);
      expect(const AutoCachePolicy(percent: 500).fraction, 1.0);
    });

    test('unknown duration never reaches the point', () {
      expect(const AutoCachePolicy().cachePoint(track(duration: null)),
          Duration.zero);
    });
  });

  group('saving a track', () {
    test('one listen is enough, no repeat required', () {
      const policy = AutoCachePolicy();
      expect(policy.shouldCache(track(plays: 0)), isTrue);
    });

    test('replaying a song does not change the decision', () {
      const policy = AutoCachePolicy();
      expect(policy.shouldCache(track(plays: 1)), isTrue);
      expect(policy.shouldCache(track(plays: 9)), isTrue);
    });

    test('skips are irrelevant, only finishing matters', () {
      const policy = AutoCachePolicy();
      expect(policy.shouldCache(track(plays: 3, skips: 3)), isTrue);
    });

    test('respects the auto-cache switch', () {
      const policy = AutoCachePolicy(enabled: false);
      expect(policy.shouldCache(track()), isFalse);
      expect(policy.shouldCache(track(favorite: true)), isTrue);
    });

    test('never re-caches something already cached', () {
      const policy = AutoCachePolicy();
      expect(policy.shouldCache(track(audioPath: '/audio/x.m4a')), isFalse);
    });

    test('podcast-length uploads need a manual save', () {
      const policy = AutoCachePolicy();
      expect(policy.shouldCache(track(duration: 45 * 60)), isFalse);
    });
  });
}
