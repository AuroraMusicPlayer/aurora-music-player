import 'package:audio_service/audio_service.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'app_events.dart';
import 'debug_harness.dart';
import 'debug_signin.dart';
import 'audio/audio_handler.dart';
import 'data/device_cache.dart';
import 'data/artwork_cache.dart';
import 'data/google_account.dart';
import 'data/youtube_api.dart';
import 'data/library.dart';
import 'data/playback_memory.dart';
import 'data/youtube_source.dart';
import 'settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop has no sqflite implementation; the FFI factory covers macOS,
  // Windows and Linux with the same SQLite engine.
  final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  if (isDesktop) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final settings = await Settings.load();
  final library = await Library.open(
    directory: isDesktop ? (await getApplicationSupportDirectory()).path : null,
  );
  final metadata = YouTubeApi();
  final source = YouTubeSource(metadata: metadata);
  final events = AppEvents();
  final memory = await PlaybackMemory.load();
  final artwork = ArtworkCache();
  final google = GoogleAccount();
  final cache = DeviceCache(library: library, source: source, settings: settings);

  // audio_service has no Windows or Linux implementation. Playback still works
  // there through just_audio where the platform supports it; the media session,
  // notification and car integration simply do not exist.
  final supportsAudioService = Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  AuroraAudioHandler buildHandler() => AuroraAudioHandler(
      source: source,
      library: library,
      cache: cache,
      settings: settings,
      events: events,
      memory: memory,
      artwork: artwork,
  );

  final handler = supportsAudioService
      ? await AudioService.init(
          builder: buildHandler,
          config: const AudioServiceConfig(
            androidNotificationChannelId: 'dev.aurora.music',
            androidNotificationChannelName: 'Aurora Music',
            androidNotificationOngoing: true,
            androidStopForegroundOnPause: true,
          ),
        )
      : buildHandler();

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
        metadata: metadata,
      ),
    ),
  );

  // No-op unless AURORA_DEMO_SIGNIN is set.
  // ignore: unawaited_futures
  runSignInProbe(google);

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
      metadata: metadata,
    ),
  );
}
