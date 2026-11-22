import 'package:flutter/material.dart';

import '../app.dart';
import 'package:audio_service/audio_service.dart';

Future<void> showQueueSheet(BuildContext context, AppServices services) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFF101010),
    builder: (_) => QueueSheet(services: services),
  );
}

/// Drag to reorder, swipe to remove, tap to jump.
class QueueSheet extends StatefulWidget {
  const QueueSheet({super.key, required this.services});

  final AppServices services;

  @override
  State<QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends State<QueueSheet> {
  @override
  Widget build(BuildContext context) {
    final handler = widget.services.handler;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: StreamBuilder<List<MediaItem>>(
        stream: handler.queue.stream,
        builder: (context, snapshot) {
          final tracks = snapshot.data ?? const <MediaItem>[];
          final current = handler.player.currentIndex ?? -1;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    const Text('Queue',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(width: 8),
                    Text('${tracks.length} songs',
                        style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        handler.autoplayEnabled.value =
                            !handler.autoplayEnabled.value;
                        setState(() {});
                      },
                      icon: Icon(
                        handler.autoplayEnabled.value
                            ? Icons.auto_awesome
                            : Icons.auto_awesome_outlined,
                        size: 16,
                      ),
                      label: Text(handler.autoplayEnabled.value
                          ? 'Autoplay on'
                          : 'Autoplay off'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: tracks.length,
                  onReorder: (oldIndex, newIndex) async {
                    await handler.reorder(oldIndex, newIndex);
                    setState(() {});
                  },
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    final isCurrent = index == current;

                    return Dismissible(
                      key: ValueKey('queue-${track.id}-$index'),
                      direction: DismissDirection.endToStart,
                      background: const ColoredBox(
                        color: Color(0xFF2A1212),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: EdgeInsets.only(right: 20),
                            child: Icon(Icons.delete_outline),
                          ),
                        ),
                      ),
                      onDismissed: (_) async {
                        await handler.removeAt(index);
                        setState(() {});
                      },
                      child: ListTile(
                        onTap: () async {
                          await handler.jumpTo(index);
                          if (context.mounted) Navigator.pop(context);
                        },
                        leading: SizedBox(
                          width: 44,
                          height: 44,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: track.artUri == null
                                ? const ColoredBox(color: Color(0xFF1E1E1E))
                                : Image.network(track.artUri.toString(), fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const ColoredBox(color: Color(0xFF1E1E1E))),
                          ),
                        ),
                        title: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isCurrent
                                ? Theme.of(context).colorScheme.primary
                                : null,
                            fontWeight: isCurrent ? FontWeight.w600 : null,
                          ),
                        ),
                        subtitle: Text(track.artist ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12)),
                        trailing: ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Icons.drag_handle,
                              color: Colors.white38),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
