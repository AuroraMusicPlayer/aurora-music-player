import 'package:flutter/material.dart';

import 'app_events.dart';
import 'audio/audio_handler.dart';
import 'data/device_cache.dart';
import 'data/library.dart';
import 'data/youtube_source.dart';
import 'settings.dart';
import 'ui/home_screen.dart';

/// Everything long-lived, created once in `main()` and passed down.
class AppServices {
  AppServices({
    required this.settings,
    required this.library,
    required this.source,
    required this.cache,
    required this.handler,
    required this.events,
  });

  final Settings settings;
  final Library library;
  final YouTubeSource source;
  final DeviceCache cache;
  final AuroraAudioHandler handler;
  final AppEvents events;
}

class AuroraApp extends StatelessWidget {
  const AuroraApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final dark = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF7C5CFF),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    );

    return MaterialApp(
      title: 'Aurora Music',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: dark,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7C5CFF)),
        useMaterial3: true,
      ),
      home: HomeScreen(services: services),
    );
  }
}
