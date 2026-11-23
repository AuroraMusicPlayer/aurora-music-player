import 'package:flutter_test/flutter_test.dart';

import 'package:aurora_music/data/models.dart';
import 'package:aurora_music/data/music_filter.dart';

Track t(String title, String artist, {int? duration = 200}) =>
    Track(id: 'x', title: title, artist: artist, duration: duration);

void main() {
  group('music filter', () {
    test('keeps ordinary songs', () {
      expect(MusicFilter.isMusic(t('Instant Crush', 'Daft Punk', duration: 340)), isTrue);
      expect(MusicFilter.isMusic(t('PMW', 'Noizy', duration: 180)), isTrue);
    });

    test('rejects hour-long uploads', () {
      expect(MusicFilter.isMusic(t('Best of 2026', 'DJ Set', duration: 60 * 60)), isFalse);
    });

    test('rejects podcast and talk episodes by title', () {
      expect(MusicFilter.isMusic(t('Episode 42: the state of music', 'Some Show')), isFalse);
      expect(MusicFilter.isMusic(t('Interview with a producer', 'Studio')), isFalse);
      expect(MusicFilter.isMusic(t('Daily news roundup', 'Channel')), isFalse);
    });

    test('rejects show channels', () {
      expect(MusicFilter.isMusic(t('Morning mix', 'Talks Network')), isFalse);
      expect(MusicFilter.isMusic(t('Weekly', 'The Music Podcast')), isFalse);
    });

    test('songsOnly never returns an empty list', () {
      final onlyShows = [
        t('Episode 1', 'Podcast Network'),
        t('Episode 2', 'Podcast Network'),
      ];
      expect(MusicFilter.songsOnly(onlyShows), hasLength(2));
    });

    test('songsOnly removes the shows and keeps the songs', () {
      final mixed = [
        t('Podcast episode 12', 'Talks'),
        t('PMW', 'Noizy'),
      ];
      final filtered = MusicFilter.songsOnly(mixed);
      expect(filtered, hasLength(1));
      expect(filtered.single.title, 'PMW');
    });
  });
}
