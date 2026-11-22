import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'app_events.dart';
import 'debug_harness.dart';
import 'audio/audio_handler.dart';
import 'data/device_cache.dart';
import 'data/artwork_cache.dart';
import 'data/google_account.dart';
import 'data/library.dart';
import 'data/playback_memory.dart';
import 'data/youtube_source.dart';
import 'settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settings = await Settings.load();
  final library = await Library.open();
  final source = YouTubeSource();
  final events = AppEvents();
  final memory = await PlaybackMemory.load();
  final artwork = ArtworkCache();
  final google = GoogleAccount();
  final cache = DeviceCache(library: library, source: source, settings: settings);

  final handler = await AudioService.init(
    builder: () => AuroraAudioHandler(
      source: source,
      library: library,
      cache: cache,
      settings: settings,
      events: events,
      memory: memory,
      artwork: artwork,
    ),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'dev.aurora.music',
      androidNotificationChannelName: 'Aurora Music',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  runApp(
    AuroraApp(
      services: AppServices(
        settings: settings,
        library: library,
        source: source,
        cache: cache,
        handler: handler,
        events: events,
        memory: memory,
        artwork: artwork,
        google: google,
      ),
    ),
  );

  // No-op unless the simulator QA define is set.
  // ignore: unawaited_futures
  runDemoHarness(
    AppServices(
      settings: settings,
      library: library,
      source: source,
      cache: cache,
      handler: handler,
      events: events,
      memory: memory,
      artwork: artwork,
      google: google,
    ),
  );
}
