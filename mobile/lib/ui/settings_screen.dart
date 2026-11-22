import 'package:flutter/material.dart';

import '../app.dart';
import '../data/google_account.dart';
import '../data/models.dart';
import 'google_import.dart';
import 'youtube_sync_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _usageBytes = 0;
  GoogleUser? _googleUser;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _googleUser = widget.services.google.user;
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

  List<Widget> _googleSection(AppServices services) {
    final google = services.google;

    if (!google.isConfigured) {
      return [
        ListTile(
          leading: const Icon(Icons.key_off_outlined),
          title: const Text('Not configured in this build'),
          subtitle: Text(google.missingConfigHint,
              style: const TextStyle(fontSize: 12)),
        ),
      ];
    }

    final user = _googleUser;
    if (user == null) {
      return [
        ListTile(
          leading: _connecting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.login),
          title: const Text('Connect Google account'),
          subtitle: const Text(
            'Import your YouTube playlists and liked songs, and keep them in sync',
            style: TextStyle(fontSize: 12),
          ),
          onTap: _connecting ? null : _connect,
        ),
      ];
    }

    return [
      ListTile(
        leading: const Icon(Icons.account_circle_outlined),
        title: Text(user.email ?? 'Connected'),
        subtitle: const Text('YouTube library access',
            style: TextStyle(fontSize: 12)),
        trailing: TextButton(
          onPressed: _disconnect,
          child: const Text('Sign out'),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.sync),
        title: const Text('Sync with YouTube Music'),
        subtitle: const Text(
          'Likes and playlists, both directions. Additions only — nothing is '
          'deleted remotely.',
          style: TextStyle(fontSize: 12),
        ),
        onTap: () => showYoutubeSync(context, services, onDone: () => setState(() {})),
      ),
      ListTile(
        leading: const Icon(Icons.cloud_download_outlined),
        title: const Text('Import YouTube library'),
        subtitle: const Text(
          'Playlists and liked songs, with an option to save them offline',
          style: TextStyle(fontSize: 12),
        ),
        onTap: () => showGoogleImport(context, services),
      ),
    ];
  }

  Future<void> _connect() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _connecting = true);
    try {
      final user = await widget.services.google.signIn();
      if (!mounted) return;
      setState(() => _googleUser = user);
      if (user == null) {
        messenger.showSnackBar(const SnackBar(content: Text('Sign-in cancelled')));
      }
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _disconnect() async {
    await widget.services.google.signOut();
    if (!mounted) return;
    setState(() => _googleUser = null);
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
              const _SectionHeader('Google account'),
              ..._googleSection(services),

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
              ListTile(
                dense: true,
                title: const Text('Version'),
                trailing: Text(appVersion,
                    style: const TextStyle(fontSize: 12, color: Colors.white38)),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  'Aurora Music — personal build. Audio is resolved on the device '
                  'and cached locally; no server is involved. Android Auto browsing '
                  'is supported; CarPlay needs an Apple-granted entitlement that '
                  'self-signed builds cannot obtain.',
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
