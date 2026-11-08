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
  final _c = ScrollController();
  int _lastIdx = -2;
  double _lastH = 0;

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
    final settings = context.watch<SettingsProvider>();
    final showTr = lyrics.hasTranslation;
    final showRo = lyrics.hasRomaji;
    final h = 34.0 + (showRo ? 20 : 0) + (showTr ? 24 : 0); // tinggi tiap baris

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
        final pl = lyrics.plainLines;
        body = SingleChildScrollView(
          child: Column(children: [
            for (var i = 0; i < pl.length; i++) ...[
              SizedBox(
                width: double.infinity,
                child: Text(pl[i],
                    textAlign: TextAlign.center,
                    style: t.titleStyle.copyWith(
                        fontSize: 13, height: 1.6, fontWeight: FontWeight.w400)),
              ),
              if (lyrics.romajiAt(i) != null)
                SizedBox(
                  width: double.infinity,
                  child: Text(lyrics.romajiAt(i)!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: Colors.white.withValues(alpha: 0.6))),
                ),
              if (lyrics.translationAt(i) != null)
                SizedBox(
                  width: double.infinity,
                  child: Text(lyrics.translationAt(i)!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          fontStyle: FontStyle.italic,
                          color: t.accentColor.withValues(alpha: 0.8))),
                ),
            ],
          ]),
        );
      case LyricsState.synced:
        body = LayoutBuilder(builder: (context, box) {
          final idx = lyrics.indexAt(music.position);
          if (idx != _lastIdx || h != _lastH) {
            _lastIdx = idx;
            _lastH = h;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!_c.hasClients) return;
              final target = (idx < 0 ? 0 : idx) * h;
              _c.animateTo(
                target.clamp(0.0, _c.position.maxScrollExtent).toDouble(),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
              );
            });
          }
          final pad = (box.maxHeight - h) / 2;
          return ListView.builder(
            controller: _c,
            itemExtent: h,
            padding: EdgeInsets.symmetric(vertical: pad < 0 ? 0 : pad),
            itemCount: lyrics.lines.length,
            itemBuilder: (_, i) {
              final line = lyrics.lines[i];
              final d = (i - idx).abs();
              final current = i == idx;
              final opacity = current ? 1.0 : (d == 1 ? 0.6 : (d == 2 ? 0.4 : 0.25));
              final tl = lyrics.translationAt(i);
              final ro = lyrics.romajiAt(i);
              return Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      line.text.isEmpty ? '♪' : line.text,
                      style: TextStyle(
                        fontSize: current ? 17 : 13,
                        fontWeight: current ? FontWeight.w700 : FontWeight.w400,
                        color: (current ? t.accentColor : Colors.white)
                            .withValues(alpha: opacity),
                      ),
                    ),
                    if (ro != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          ro,
                          style: TextStyle(
                            fontSize: current ? 12.5 : 10.5,
                            color: Colors.white.withValues(alpha: opacity * 0.7),
                          ),
                        ),
                      ),
                    if (tl != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          tl,
                          style: TextStyle(
                            fontSize: current ? 13 : 11,
                            fontStyle: FontStyle.italic,
                            color: Colors.white.withValues(alpha: opacity * 0.85),
                          ),
                        ),
                      ),
                  ]),
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
            const SizedBox(width: 6),
            Tooltip(
              message: settings.lyricsTranslate
                  ? tr(context, 'Terjemahan: nyala (${settings.lyricsTargetLang})',
                      'Translation: on (${settings.lyricsTargetLang})')
                  : tr(context, 'Terjemahan: mati', 'Translation: off'),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => settings.setLyricsTranslate(!settings.lyricsTranslate),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: lyrics.translating
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.6, color: t.accentColor))
                      : Icon(Icons.translate,
                          size: 15,
                          color: settings.lyricsTranslate
                              ? t.accentColor
                              : Colors.white38),
                ),
              ),
            ),
            const SizedBox(width: 6),
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
