import 'package:flutter/material.dart';

import '../app.dart';
import 'home_tab.dart';
import 'library_tab.dart';
import 'mini_player.dart';
import 'player_sheet.dart';
import 'settings_screen.dart';
import 'search_tab.dart';

/// Shell: three tabs, a persistent mini player, and one place that surfaces
/// playback errors so a failed track never looks like a frozen player.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Defaults to Home; `--dart-define=AURORA_START_TAB=1|2` opens Search or
  /// Library, which is how the screens get inspected in a simulator.
  int _tab = int.tryParse(const String.fromEnvironment('AURORA_START_TAB')) ?? 0;

  @override
  void initState() {
    super.initState();
    widget.services.handler.error.addListener(_showError);
  }

  @override
  void dispose() {
    widget.services.handler.error.removeListener(_showError);
    super.dispose();
  }

  void _showError() {
    final message = widget.services.handler.error.value;
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // `--dart-define=AURORA_START_TAB=3` renders the player directly, which is
    // how its layout is inspected in a simulator without tapping.
    if (_tab == 3) {
      return PlayerScreen(services: widget.services);
    }
    if (_tab == 4) {
      return SettingsScreen(services: widget.services);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF030303),
      body: IndexedStack(
        index: _tab,
        children: [
          HomeTab(
            services: widget.services,
            onOpenSearch: () => setState(() => _tab = 1),
          ),
          SearchTab(services: widget.services),
          LibraryTab(services: widget.services),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MiniPlayer(services: widget.services),
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (index) => setState(() => _tab = index),
            backgroundColor: const Color(0xFF0A0A0A),
            indicatorColor: Colors.white10,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
              NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: 'Library'),
            ],
          ),
        ],
      ),
    );
  }
}
