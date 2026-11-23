import 'package:flutter_test/flutter_test.dart';

import 'package:aurora_music/data/models.dart';
import 'package:aurora_music/data/search_ranker.dart';

Track t(String id, String title, String artist, {int duration = 200}) => Track(
      id: id,
      title: title,
      artist: artist,
      duration: duration,
    );

void main() {
  group('search ranking', () {
    test('a known artist beats a same-titled song from someone else', () {
      // The real complaint: "noizy pwa" surfaced an unrelated song whose title
      // contained PWA.
      final results = [
        t('indian', 'Pwa Pwa', 'Bollywood Singer'),
        t('noizy', 'PWA', 'Noizy'),
        t('other', 'Some Other Song', 'Unrelated Band'),
      ];

      final ranked = const SearchRanker({'noizy': 6}).rank('noizy pwa', results);

      expect(ranked.first.id, 'noizy');
    });

    test('when enough results come from the known artist, others are dropped', () {
      final results = [
        t('wrong1', 'Pwa', 'Random Artist'),
        t('a', 'Pwa', 'Noizy'),
        t('b', 'Pwa (Remix)', 'Noizy'),
        t('c', 'Pwa Live', 'Noizy'),
      ];

      final ranked = const SearchRanker({'noizy': 4}).rank('noizy pwa', results);

      expect(ranked.length, 3);
      expect(ranked.every((track) => track.artist == 'Noizy'), isTrue);
      expect(ranked.any((track) => track.id == 'wrong1'), isFalse);
    });

    test('without history the original order is kept', () {
      final results = [
        t('first', 'Song A', 'Artist A'),
        t('second', 'Song B', 'Artist B'),
      ];

      final ranked = const SearchRanker({}).rank('unrelated query', results);

      expect(ranked.map((track) => track.id).toList(), ['first', 'second']);
    });

    test('affinity lifts an artist the library plays a lot', () {
      final results = [
        t('x', 'Track', 'Niche Artist'),
        t('y', 'Track', 'Favourite Artist'),
      ];

      final ranked = const SearchRanker({'favourite artist': 9}).rank('track', results);

      expect(ranked.first.id, 'y');
    });

    test('a query with no recognisable artist keeps every result', () {
      final results = [
        t('a', 'Hello', 'Adele'),
        t('b', 'Hello', 'Lionel Richie'),
        t('c', 'Hello', 'Some Cover Band'),
      ];

      final ranked = const SearchRanker({'adele': 3}).rank('hello', results);

      expect(ranked.length, 3);
    });
  });
}
