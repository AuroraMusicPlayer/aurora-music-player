import 'package:flutter/material.dart';

import 'app_events.dart';
import 'audio/audio_handler.dart';
import 'data/device_cache.dart';
import 'data/artwork_cache.dart';
import 'data/library.dart';
import 'data/playback_memory.dart';
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
    required this.memory,
    required this.artwork,
  });

  final Settings settings;
  final Library library;
  final YouTubeSource source;
  final DeviceCache cache;
  final AuroraAudioHandler handler;
  final AppEvents events;
  final PlaybackMemory memory;
  final ArtworkCache artwork;
}

class AuroraApp extends StatelessWidget {
  const AuroraApp({super.key, required this.services});

  /// Needed by the simulator QA harness to push the player without a tap.
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF030303);
    const surface = Color(0xFF141414);

    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF8B5CF6),
      brightness: Brightness.dark,
    ).copyWith(surface: background);

    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF0A0A0A),
        indicatorColor: Colors.white10,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
            color: states.contains(WidgetState.selected)
                ? Colors.white
                : Colors.white54,
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: Colors.white70,
        textColor: Colors.white,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      textTheme: Typography.whiteMountainView.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
    );

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Aurora Music',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      home: HomeScreen(services: services),
    );
  }
}
