import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../data/youtube_library.dart';
import '../data/youtube_sync.dart';

/// Runs a two-way sync and reports what changed.
Future<void> showYoutubeSync(
  BuildContext context,
  AppServices services, {
  VoidCallback? onDone,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final status = ValueNotifier<String>('Preparing…');

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

    final result = await sync.run(onStatus: (message) => status.value = message);
    services.events.bump();

    if (context.mounted) Navigator.of(context).pop();
    final summary = result.summary.isEmpty ? 'Already in sync' : result.summary;
    messenger.showSnackBar(SnackBar(
      content: Text(summary),
      duration: const Duration(seconds: 6),
    ));
    if (result.warnings.isNotEmpty) {
      messenger.showSnackBar(SnackBar(
        content: Text(result.warnings.first),
        duration: const Duration(seconds: 6),
      ));
    }
    onDone?.call();
  } catch (error) {
    if (context.mounted) Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text('$error')));
  } finally {
    sync?.dispose();
    reader?.dispose();
  }
}
