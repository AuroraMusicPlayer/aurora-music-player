import 'package:flutter/material.dart';

import '../app.dart';
import '../data/models.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _usageBytes = 0;

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadUsage() async {
    final bytes = await widget.services.cache.usageBytes();
    if (mounted) setState(() => _usageBytes = bytes);
  }

  Future<void> _clearAutoCached() async {
    final library = widget.services.library;
    final removed = <Track>[];
    for (final track in await library.evictable()) {
      await widget.services.cache.remove(track);
      removed.add(track);
    }
    await _loadUsage();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Removed ${removed.length} auto-cached tracks')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    final settings = services.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AnimatedBuilder(
        animation: settings,
        builder: (context, _) {
          final usedMb = _usageBytes / (1024 * 1024);
          return ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              const _SectionHeader('Automatic caching'),
              SwitchListTile(
                title: const Text('Save tracks I replay'),
                subtitle: Text(
                  'Saves a track when you replay it '
                  '${settings.autoCacheThreshold}× — or when you listen almost all '
                  'the way through it once.',
                ),
                value: settings.autoCacheEnabled,
                onChanged: (value) => settings.autoCacheEnabled = value,
              ),
              _StepperTile(
                title: 'Plays before saving',
                subtitle: 'A play counts after 30 seconds, or half the track if shorter.',
                value: settings.autoCacheThreshold,
                min: 1,
                max: 10,
                onChanged: (value) => settings.autoCacheThreshold = value,
              ),
              SwitchListTile(
                title: const Text('Only on Wi-Fi'),
                subtitle: const Text('Avoid spending mobile data on automatic saves.'),
                value: settings.wifiOnly,
                onChanged: (value) => settings.wifiOnly = value,
              ),

              const _SectionHeader('Storage'),
              _StepperTile(
                title: 'Cache budget',
                subtitle: 'Auto-cached tracks are removed least-recently-played first. '
                    'Favourites and manual saves are never removed.',
                value: settings.cacheBudgetGb,
                min: 1,
                max: 64,
                suffix: 'GB',
                onChanged: (value) => settings.cacheBudgetGb = value,
              ),
              ListTile(
                title: const Text('Used'),
                subtitle: Text('${usedMb.toStringAsFixed(1)} MB of ${settings.cacheBudgetGb} GB'),
                trailing: TextButton(
                  onPressed: _usageBytes == 0 ? null : _clearAutoCached,
                  child: const Text('Clear auto-cached'),
                ),
              ),

              const _SectionHeader('About'),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  'Aurora Music — personal build. Audio is resolved by your own Mac '
                  'and cached locally. Android Auto and CarPlay arrive in a later phase.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _StepperTile extends StatelessWidget {
  const _StepperTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.suffix = '',
  });

  final String title;
  final String subtitle;
  final int value;
  final int min;
  final int max;
  final String suffix;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value <= min ? null : () => onChanged(value - 1),
          ),
          Text('$value$suffix', style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value >= max ? null : () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}
