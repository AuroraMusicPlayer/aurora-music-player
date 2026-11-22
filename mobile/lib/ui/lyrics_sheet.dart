import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../data/lyrics.dart';
import '../data/models.dart';

Future<void> showLyricsSheet(
  BuildContext context,
  AppServices services,
  Track track,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFF101010),
    builder: (_) => LyricsSheet(services: services, track: track),
  );
}

class LyricsSheet extends StatefulWidget {
  const LyricsSheet({super.key, required this.services, required this.track});

  final AppServices services;
  final Track track;

  @override
  State<LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<LyricsSheet> {
  final _client = LyricsClient();
  final _scroll = ScrollController();

  Lyrics? _lyrics;
  bool _loading = true;
  bool _notFound = false;
  int _activeLine = -1;
  StreamSubscription<Duration>? _positionSub;

  @override
  void initState() {
    super.initState();
    _load();
    _positionSub = widget.services.handler.player.positionStream.listen(_onPosition);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _scroll.dispose();
    _client.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final lyrics = await _client.forTrack(
      title: widget.track.title,
      artist: widget.track.artist,
      durationSeconds: widget.track.duration,
    );
    if (!mounted) return;
    setState(() {
      _lyrics = lyrics;
      _loading = false;
      _notFound = lyrics == null;
    });
  }

  void _onPosition(Duration position) {
    final lyrics = _lyrics;
    if (lyrics == null || !lyrics.synced || lyrics.lines.isEmpty) return;

    var index = -1;
    for (var i = 0; i < lyrics.lines.length; i++) {
      if (position >= lyrics.lines[i].at) {
        index = i;
      } else {
        break;
      }
    }
    if (index == _activeLine) return;

    setState(() => _activeLine = index);
    if (index >= 0) _scrollTo(index);
  }

  void _scrollTo(int index) {
    if (!_scroll.hasClients) return;
    final target = (index * 44.0) - 120;
    _scroll.animateTo(
      target.clamp(0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text(widget.track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_notFound || _lyrics == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No lyrics found for this track.\nlyrics come from lrclib.net, a '
            'community database — not every song is there.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
      );
    }

    final lyrics = _lyrics!;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      itemCount: lyrics.lines.length,
      itemBuilder: (context, index) {
        final line = lyrics.lines[index];
        final active = lyrics.synced && index == _activeLine;

        return GestureDetector(
          onTap: lyrics.synced
              ? () => widget.services.handler.seek(line.at)
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              line.text,
              style: TextStyle(
                fontSize: active ? 20 : 17,
                height: 1.35,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                color: active ? Colors.white : Colors.white60,
              ),
            ),
          ),
        );
      },
    );
  }
}
