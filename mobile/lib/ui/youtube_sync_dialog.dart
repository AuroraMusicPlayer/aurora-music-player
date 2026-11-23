import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../data/google_account.dart';
import '../data/youtube_library.dart';
import '../data/youtube_sync.dart';

/// Runs a two-way sync and reports what changed.
///
/// If Google rejects the stored token — which happens every seven days for apps
/// in Testing mode — it offers a reconnect instead of failing with a 401.
Future<void> showYoutubeSync(
  BuildContext context,
  AppServices services, {
  VoidCallback? onDone,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final status = ValueNotifier<String>('Preparing…');

  Future<SyncResult?> attempt() async {
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Syncing'),
        content: ValueListenableBuilder<String>(
          valueListenable: status,
          builder: (context, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    ));

    YouTubeLibrary? reader;
    YouTubeSync? sync;
    try {
      reader = YouTubeLibrary(services.google);
      sync = YouTubeSync(
        account: services.google,
        library: services.library,
        reader: reader,
      );
      return await sync.run(
        onStatus: (message) => status.value = message,
        pullOnly: services.settings.youtubePullOnly,
      );
    } finally {
      sync?.dispose();
      reader?.dispose();
    }
  }

  try {
    SyncResult? result;
    try {
      result = await attempt();
    } on GoogleAuthExpired {
      if (context.mounted) Navigator.of(context).pop();
      final reconnect = await _askReconnect(context);
      if (reconnect != true) return;
      final user = await services.google.signIn();
      if (user == null) return;
      result = await attempt();
    }

    if (context.mounted) Navigator.of(context).pop();
    services.events.bump();

    final summary = (result?.summary.isEmpty ?? true) ? 'Already in sync' : result!.summary;
    messenger.showSnackBar(SnackBar(
      content: Text(summary),
      duration: const Duration(seconds: 6),
    ));
    if (result != null && result.warnings.isNotEmpty) {
      messenger.showSnackBar(SnackBar(
        content: Text(result.warnings.first),
        duration: const Duration(seconds: 6),
      ));
    }
    onDone?.call();
  } catch (error) {
    if (context.mounted) Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text('$error')));
  }
}

Future<bool?> _askReconnect(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Google session expired'),
      content: const Text(
        'Apps in Testing mode need re-authorisation every seven days. '
        'Reconnect to keep syncing your likes and playlists.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Reconnect'),
        ),
      ],
    ),
  );
}
