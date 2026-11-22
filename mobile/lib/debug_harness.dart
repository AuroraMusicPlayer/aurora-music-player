
import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'data/models.dart';
import 'ui/player_sheet.dart';

/// Simulator-only scaffolding, driven by `--dart-define` so it never runs in a
/// normal build.
///
///   flutter run --dart-define=AURORA_DEMO_VIDEO=<youtubeId>
///               [--dart-define=AURORA_DEMO_TITLE=...]
///               [--dart-define=AURORA_DEMO_ARTIST=...]
///               [--dart-define=AURORA_DEMO_OPEN_PLAYER=1]
///
/// It exists so the player and the now-playing surfaces can be inspected
/// without a human tapping through the app.
const demoVideoId = String.fromEnvironment('AURORA_DEMO_VIDEO');
const demoTitle = String.fromEnvironment('AURORA_DEMO_TITLE', defaultValue: 'Instant Crush');
const demoArtist = String.fromEnvironment('AURORA_DEMO_ARTIST', defaultValue: 'Daft Punk');
const demoOpenPlayer = String.fromEnvironment('AURORA_DEMO_OPEN_PLAYER') == '1';

Future<void> runDemoHarness(AppServices services) async {
  if (demoVideoId.isEmpty) return;

  // Let the first frame settle so the shell is mounted.
  await Future<void>.delayed(const Duration(milliseconds: 900));

  final track = Track(
    id: demoVideoId,
    title: demoTitle,
    artist: demoArtist,
    duration: 340,
    thumbnail: 'https://i.ytimg.com/vi/$demoVideoId/hqdefault.jpg',
  );

  await services.library.remember(track);
  await services.handler.playTracks([track]);

  if (!demoOpenPlayer) return;

  await Future<void>.delayed(const Duration(seconds: 2));
  final navigator = AuroraApp.navigatorKey.currentState;
  if (navigator == null) {
    debugPrint('demo: navigator not ready');
    return;
  }
  debugPrint('demo: opening player');
  unawaited(navigator.push(
    MaterialPageRoute<void>(builder: (_) => PlayerScreen(services: services)),
  ));
}
