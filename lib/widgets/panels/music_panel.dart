import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/music_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/island_theme.dart';
import '../visualizers/adaptive_visualizer.dart';

class MusicPanel extends StatelessWidget {
  const MusicPanel({super.key});

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Color _sourceColor(MusicSource s) => switch (s) {
        MusicSource.spotify => const Color(0xFF1DB954),
        MusicSource.youtubeMusic => const Color(0xFFFF0033),
        MusicSource.appleMusic => const Color(0xFFFA243C),
        MusicSource.soundcloud => const Color(0xFFFF5500),
        MusicSource.other => Colors.white54,
      };

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicProvider>();
    final settings = context.watch<SettingsProvider>();
    final l10n = AppLocalizations.of(context)!;
    final t = settings.theme;
    final has = music.hasTrack;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.music_note, size: 14, color: t.accentColor),
            const SizedBox(width: 6),
            Text(l10n.nowPlaying,
                style: t.subtitleStyle.copyWith(letterSpacing: 1)),
            const Spacer(),
            if (has && music.sourceName.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: _sourceColor(music.source).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(music.sourceName,
                    style: TextStyle(
                        color: _sourceColor(music.source),
                        fontSize: 9,
                        fontWeight: FontWeight.w600)),
              ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _Art(url: has ? music.artUrl : null, accent: t.accentColor, bg: t.expandedColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(has ? music.title : l10n.noTrack,
                      style: t.titleStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(has ? music.artist : l10n.playerHint,
                      style: t.subtitleStyle,
                      maxLines: has ? 1 : 2,
                      overflow: TextOverflow.ellipsis),
                  if (has && music.album.isNotEmpty)
                    Text(music.album,
                        style: t.subtitleStyle.copyWith(fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Visualizer di samping judul; bentuknya mengikuti mode pilihan.
            SizedBox(
              width: (settings.vizMode == VisualizerMode.circularWave ||
                      settings.vizMode == VisualizerMode.particleSystem)
                  ? 64
                  : 96,
              height: 56,
              child: AdaptiveVisualizer(
                spectrum: music.spectrum,
                color: t.accentColor,
                mode: settings.vizMode,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: has ? music.progress : 0,
              minHeight: 3,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation(t.accentColor),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(has ? music.position : Duration.zero),
                  style: t.subtitleStyle),
              Text(_fmt(has ? music.duration : Duration.zero),
                  style: t.subtitleStyle),
            ],
          ),
          const SizedBox(height: 16),
          Opacity(
            opacity: has ? 1 : 0.35,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: has ? music.previous : null,
                  child: const Icon(Icons.skip_previous,
                      color: Colors.white70, size: 22),
                ),
                const SizedBox(width: 20),
                GestureDetector(
                  onTap: has ? music.toggle : null,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: t.accentColor, shape: BoxShape.circle),
                    child: Icon(
                        music.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.black,
                        size: 22),
                  ),
                ),
                const SizedBox(width: 20),
                GestureDetector(
                  onTap: has ? music.next : null,
                  child: const Icon(Icons.skip_next,
                      color: Colors.white70, size: 22),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Art extends StatelessWidget {
  const _Art({required this.url, required this.accent, required this.bg});
  final String? url;
  final Color accent, bg;

  @override
  Widget build(BuildContext context) {
    Widget placeholder() => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [accent.withValues(alpha: 0.6), bg]),
          ),
          child: const Icon(Icons.album, color: Colors.white54, size: 28),
        );

    Widget child = placeholder();
    final u = url;
    if (u != null && u.isNotEmpty) {
      if (u.startsWith('http')) {
        child = Image.network(u,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => placeholder());
      } else if (u.startsWith('file://')) {
        child = Image.file(File(Uri.parse(u).toFilePath()),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => placeholder());
      }
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(width: 56, height: 56, child: child),
    );
  }
}
