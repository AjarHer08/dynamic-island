import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/lyrics_provider.dart';
import '../../providers/music_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/tr.dart';

class LyricsPanel extends StatefulWidget {
  const LyricsPanel({super.key});

  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel> {
  static const _h = 34.0; // tinggi tiap baris lirik
  final _c = ScrollController();
  int _lastIdx = -2;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = context.watch<LyricsProvider>();
    final music = context.watch<MusicProvider>();
    final t = context.watch<SettingsProvider>().theme;
    final l10n = AppLocalizations.of(context)!;

    Widget message(String text, {bool spinner = false}) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (spinner)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            Text(text, style: t.subtitleStyle, textAlign: TextAlign.center),
          ]),
        );

    Widget body;
    switch (lyrics.state) {
      case LyricsState.idle:
        body = message(l10n.lyricsNeedTrack);
      case LyricsState.loading:
        body = message(l10n.loadingLyrics, spinner: true);
      case LyricsState.notFound:
        body = message(l10n.noLyrics);
      case LyricsState.instrumental:
        body = message(l10n.instrumental);
      case LyricsState.offline:
        body = message(tr(
            context,
            'Tidak ada internet dan lirik belum tersimpan.\nTaruh file .lrc dengan nama sama di folder lagu.',
            'No internet and no saved lyrics.\nPut a .lrc file with the same name next to the song.'));
      case LyricsState.plain:
        body = SingleChildScrollView(
          child: Text(lyrics.plain,
              textAlign: TextAlign.center,
              style: t.titleStyle.copyWith(
                  fontSize: 13, height: 1.6, fontWeight: FontWeight.w400)),
        );
      case LyricsState.synced:
        body = LayoutBuilder(builder: (context, box) {
          final idx = lyrics.indexAt(music.position);
          if (idx != _lastIdx) {
            _lastIdx = idx;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!_c.hasClients) return;
              final target = (idx < 0 ? 0 : idx) * _h;
              _c.animateTo(
                target.clamp(0.0, _c.position.maxScrollExtent).toDouble(),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
              );
            });
          }
          final pad = (box.maxHeight - _h) / 2;
          return ListView.builder(
            controller: _c,
            itemExtent: _h,
            padding: EdgeInsets.symmetric(vertical: pad < 0 ? 0 : pad),
            itemCount: lyrics.lines.length,
            itemBuilder: (_, i) {
              final line = lyrics.lines[i];
              final d = (i - idx).abs();
              final current = i == idx;
              final opacity = current ? 1.0 : (d == 1 ? 0.6 : (d == 2 ? 0.4 : 0.25));
              return Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    line.text.isEmpty ? '♪' : line.text,
                    style: TextStyle(
                      fontSize: current ? 17 : 13,
                      fontWeight: current ? FontWeight.w700 : FontWeight.w400,
                      color: (current ? t.accentColor : Colors.white)
                          .withValues(alpha: opacity),
                    ),
                  ),
                ),
              );
            },
          );
        });
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.lyrics, size: 14, color: t.accentColor),
            const SizedBox(width: 6),
            Text(l10n.lyrics, style: t.subtitleStyle.copyWith(letterSpacing: 1)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                music.hasTrack ? '${music.title} - ${music.artist}' : '',
                style: t.subtitleStyle.copyWith(fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Expanded(child: body),
        ],
      ),
    );
  }
}
