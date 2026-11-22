import 'package:flutter_test/flutter_test.dart';

import 'package:aurora_music/data/lyrics.dart';

void main() {
  group('LRC parsing', () {
    test('reads timestamps with fraction and sorts them', () {
      final lines = LyricsClient.parseLrc('''
[00:12.50] Second line
[00:03.00] First line
''');

      expect(lines, hasLength(2));
      expect(lines.first.text, 'First line');
      expect(lines.first.at, const Duration(seconds: 3));
      expect(lines.last.at, const Duration(seconds: 12, milliseconds: 500));
    });

    test('expands a line that repeats on several timestamps', () {
      final lines = LyricsClient.parseLrc('[00:10.00][01:20.00] Chorus');
      expect(lines, hasLength(2));
      expect(lines[0].at, const Duration(seconds: 10));
      expect(lines[1].at, const Duration(minutes: 1, seconds: 20));
      expect(lines.every((l) => l.text == 'Chorus'), isTrue);
    });

    test('ignores blank and untimed lines', () {
      final lines = LyricsClient.parseLrc('no timestamp here\n\n[00:05.00] Kept');
      expect(lines, hasLength(1));
      expect(lines.single.text, 'Kept');
    });
  });
}
