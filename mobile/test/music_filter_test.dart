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

    test('rejects Albanian shows, which the English patterns missed', () {
      expect(MusicFilter.isMusic(t('Dokumentar: historia e muzikës', 'RTV')), isFalse);
      expect(MusicFilter.isMusic(t('Emisioni i mëngjesit', 'Top Channel')), isFalse);
      expect(MusicFilter.isMusic(t('Intervistë me Noizy', 'ABC News')), isFalse);
      expect(MusicFilter.isMusic(t('Podkast: pjesa 3', 'Studio')), isFalse);
      expect(MusicFilter.isMusic(t('Lajme sot', 'Klan')), isFalse);
    });

    test('still accepts ordinary Albanian songs', () {
      expect(MusicFilter.isMusic(t('PMW', 'Noizy', duration: 180)), isTrue);
      expect(MusicFilter.isMusic(t('Kiki', 'Dafina Zeqiri', duration: 200)), isTrue);
    });

    test('rejects Italian documentaries', () {
      expect(MusicFilter.isMusic(t('Documentario sui Pink Floyd', 'Rai')), isFalse);
      expect(MusicFilter.isMusic(t('Intervista al cantante', 'Sky')), isFalse);
    });

    test('rejects the business/news uploads that slipped through', () {
      expect(
        MusicFilter.isMusic(t('The return of the Nvidia CEO', 'Bloomberg Technology')),
        isFalse,
      );
      expect(MusicFilter.isMusic(t('Breaking: markets rally', 'CNBC')), isFalse);
      expect(MusicFilter.isMusic(t('Earnings call highlights', 'Investor Daily')), isFalse);
    });

    test('song-like rejects long uploads even when the title looks neutral', () {
      // 14 minutes of something called "Albanian Vibes" is not a song.
      expect(MusicFilter.isSongLike(t('Albanian Vibes', 'Channel', duration: 14 * 60)), isFalse);
      expect(MusicFilter.isSongLike(t('PMW', 'Noizy', duration: 180)), isTrue);
    });

    test('title keys treat the same recording as one song', () {
      final a = MusicFilter.titleKey('Emmène-moi');
      final b = MusicFilter.titleKey('Emmene moi (Remastered 2015)');
      final c = MusicFilter.titleKey('EMMENE MOI feat. Someone');
      expect(a, b);
      expect(a, c);
      expect(MusicFilter.titleKey('Emmène-moi'), isNot(MusicFilter.titleKey('La Bohème')));
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
