import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/settings_provider.dart';
import '../../theme/island_theme.dart';
import '../../utils/tr.dart';
import '../../services/update_service.dart';

class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key});

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  Widget _switchRow(String label, bool v, ValueChanged<bool> on, IslandTheme t) =>
      Row(children: [
        Expanded(child: Text(label, style: t.subtitleStyle.copyWith(fontSize: 11))),
        Switch(
          value: v,
          onChanged: on,
          activeThumbColor: t.accentColor,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ]);

  /// Editor warna kustom yang sedang terbuka (inline, bukan dialog).
  _ColorTarget? _editing;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>();
    final l10n = AppLocalizations.of(context)!;
    final t = s.theme;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.settings, size: 14, color: t.accentColor),
              const SizedBox(width: 6),
              Text(l10n.settings,
                  style: t.subtitleStyle.copyWith(letterSpacing: 1)),
            ]),
            const SizedBox(height: 14),

            _label(l10n.language, t),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _chip(l10n.auto, s.autoLang, () => s.setAutoLang(), t),
              _chip('English', !s.autoLang && s.locale.languageCode == 'en',
                  () => s.setLocale(const Locale('en')), t),
              _chip('Indonesia', !s.autoLang && s.locale.languageCode == 'id',
                  () => s.setLocale(const Locale('id')), t),
            ]),
            const SizedBox(height: 14),

            _label(l10n.visualStyle, t),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: VisualStyle.values
                  .map((v) => _chip(_styleLabel(v), s.style == v,
                      () => s.setStyle(v), t))
                  .toList(),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: Text(
                  tr(context, 'Efek Liquid Glass (padukan dengan gaya di atas)',
                      'Liquid Glass effect (combines with the style above)'),
                  style: t.subtitleStyle.copyWith(fontSize: 11),
                ),
              ),
              Switch(
                value: s.glass,
                onChanged: s.setGlass,
                activeThumbColor: t.accentColor,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ]),
            const SizedBox(height: 8),
            _switchRow(
                tr(context, 'Sembunyi otomatis saat tidak dipakai',
                    'Auto-hide when idle'),
                s.autoHideIdle,
                s.setAutoHideIdle,
                t),
            if (s.autoHideIdle)
              Row(children: [
                Expanded(
                  child: Text(
                      tr(context, 'Sembunyi setelah ${s.idleSeconds} detik',
                          'Hide after ${s.idleSeconds} s'),
                      style: t.subtitleStyle.copyWith(fontSize: 11)),
                ),
                SizedBox(
                  width: 140,
                  child: Slider(
                    value: s.idleSeconds.toDouble(),
                    min: 5,
                    max: 120,
                    divisions: 23,
                    activeColor: t.accentColor,
                    onChanged: (v) => s.setIdleSeconds(v.round()),
                  ),
                ),
              ]),
            _switchRow(
                tr(context, 'Sembunyi seketika saat nonton (film/anime/YouTube/game)',
                    'Hide instantly while watching (movies/anime/YouTube/games)'),
                s.hideOnVideo,
                s.setHideOnVideo,
                t),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                  tr(context,
                      'Muncul lagi: ada notifikasi/alarm, kursor ke tempat island, atau menu tray > Show.',
                      'Reappears on notification/alarm, cursor over its spot, or tray > Show.'),
                  style: t.subtitleStyle.copyWith(fontSize: 9)),
            ),
            _switchRow(
                tr(context, 'Cek pembaruan otomatis', 'Check for updates automatically'),
                s.autoUpdate,
                s.setAutoUpdate,
                t),
            Consumer<UpdateService>(builder: (_, u, __) {
              final msg = switch (u.status) {
                UpdateStatus.checking => tr(context, 'Memeriksa...', 'Checking...'),
                UpdateStatus.upToDate => tr(context, 'Sudah versi terbaru (v$kAppVersion).',
                    'You are up to date (v$kAppVersion).'),
                UpdateStatus.available => tr(context, 'Versi baru tersedia: v${u.latest}',
                    'New version available: v${u.latest}'),
                UpdateStatus.noRelease => tr(context,
                    'Belum ada rilis di GitHub (v$kAppVersion).',
                    'No release on GitHub yet (v$kAppVersion).'),
                UpdateStatus.failed => tr(context, 'Gagal memeriksa (offline?).',
                    'Could not check (offline?).'),
                UpdateStatus.idle => 'v$kAppVersion',
              };
              return Row(children: [
                Expanded(
                  child: Text(msg,
                      style: t.subtitleStyle.copyWith(
                          fontSize: 11,
                          color: u.status == UpdateStatus.available
                              ? t.accentColor
                              : null)),
                ),
                GestureDetector(
                  onTap: u.status == UpdateStatus.available ? u.openRelease : u.check,
                  child: Text(
                      u.status == UpdateStatus.available
                          ? tr(context, 'Unduh', 'Download')
                          : tr(context, 'Cek sekarang', 'Check now'),
                      style: t.subtitleStyle
                          .copyWith(fontSize: 11, color: t.accentColor)),
                ),
              ]);
            }),
            const SizedBox(height: 8),

            _label(l10n.accentColor, t),
            const SizedBox(height: 6),
            _colorRow(t, l10n,
                target: _ColorTarget.accent,
                current: s.customAccent,
                presets: _accentPresets,
                onPick: s.setCustomAccent),
            const SizedBox(height: 14),

            _label(l10n.backgroundColor, t),
            const SizedBox(height: 6),
            _colorRow(t, l10n,
                target: _ColorTarget.background,
                current: s.customBackground,
                presets: _bgPresets,
                onPick: s.setCustomBackground),
            const SizedBox(height: 14),

            _label(l10n.position, t),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: IslandPosition.values
                  .map((p) => _chip(_posLabel(p), s.position == p,
                      () => s.setPosition(p), t))
                  .toList(),
            ),
            const SizedBox(height: 14),

            _label(l10n.visualizerMode, t),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: VisualizerMode.values
                  .map((m) => _chip(_vizLabel(m), s.vizMode == m,
                      () => s.setVizMode(m), t))
                  .toList(),
            ),
            const SizedBox(height: 14),

            _label('${l10n.opacity}  ${(s.opacity * 100).toInt()}%', t),
            Slider(
              value: s.opacity,
              min: 0.5,
              max: 1.0,
              divisions: 10,
              activeColor: t.accentColor,
              onChanged: s.setOpacity,
            ),
            const SizedBox(height: 8),

            // ---- Ukuran & sudut ----
            Row(children: [
              Expanded(
                child: _label(tr(context, 'Ukuran & sudut', 'Size & corners'), t),
              ),
              if (s.hasCustomSize)
                GestureDetector(
                  onTap: s.resetSizes,
                  child: Text(tr(context, 'Kembalikan bawaan', 'Reset'),
                      style: t.subtitleStyle
                          .copyWith(fontSize: 10, color: t.accentColor)),
                ),
            ]),
            _slider(t, tr(context, 'Lebar pill', 'Pill width'), t.pillWidth,
                SettingsProvider.pillWidthRange, s.setPillWidth),
            _slider(t, tr(context, 'Tinggi pill', 'Pill height'), t.pillHeight,
                SettingsProvider.pillHeightRange, s.setPillHeight),
            _slider(t, tr(context, 'Lebar panel', 'Panel width'),
                t.expandedWidth, SettingsProvider.expWidthRange,
                s.setExpandedWidth),
            _slider(t, tr(context, 'Tinggi panel', 'Panel height'),
                t.expandedHeight, SettingsProvider.expHeightRange,
                s.setExpandedHeight),
            _slider(t, tr(context, 'Sudut pill', 'Pill corners'),
                t.borderRadius, SettingsProvider.pillRadiusRange,
                s.setPillRadius),
            _slider(t, tr(context, 'Sudut panel', 'Panel corners'),
                t.expandedRadius, SettingsProvider.expRadiusRange,
                s.setExpandedRadius),
            const SizedBox(height: 10),

            // ---- Balas pesan ----
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label(
                        tr(context, 'Kirim balasan otomatis', 'Auto-send replies'),
                        t),
                    const SizedBox(height: 2),
                    Text(
                      tr(
                          context,
                          'Tekan Enter otomatis setelah teks ditempel di aplikasi chat. '
                          'Pastikan chat yang terbuka sudah benar.',
                          'Press Enter automatically after pasting into the chat app. '
                          'Make sure the right chat is open.'),
                      style: t.subtitleStyle.copyWith(fontSize: 9),
                    ),
                  ],
                ),
              ),
              Switch(
                value: s.replyAutoSend,
                onChanged: s.setReplyAutoSend,
                activeThumbColor: t.accentColor,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ]),
            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: t.accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(Icons.speed, size: 13, color: t.accentColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(l10n.perfNote,
                      style: t.subtitleStyle.copyWith(fontSize: 9)),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  static const _accentPresets = [
    Color(0xFF0A84FF), Color(0xFF30D158), Color(0xFFFF375F), Color(0xFFFF9F0A),
    Color(0xFFBF5AF2), Color(0xFF64D2FF), Color(0xFFFFD60A), Color(0xFFFF453A),
    Color(0xFFFFFFFF),
  ];
  static const _bgPresets = [
    Color(0xFF000000), Color(0xFF14141F), Color(0xFF1A1033), Color(0xFF0B2A1F),
    Color(0xFF2A0F14), Color(0xFF1C1C1E), Color(0xFF0B2233),
  ];

  Widget _swatch(Widget child, Color? fill, bool selected, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill ?? Colors.white.withValues(alpha: 0.08),
            shape: BoxShape.circle,
            border: Border.all(
                color: selected ? Colors.white : Colors.white24,
                width: selected ? 2 : 1),
          ),
          child: child,
        ),
      );

  Widget _slider(IslandTheme t, String label, double value,
          ({double min, double max}) range, ValueChanged<double> onChanged) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 4),
        Text('$label  ${value.round()}',
            style: t.subtitleStyle.copyWith(fontSize: 10)),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: t.accentColor,
              thumbColor: t.accentColor),
          child: Slider(
            value: value.clamp(range.min, range.max).toDouble(),
            min: range.min,
            max: range.max,
            onChanged: onChanged,
          ),
        ),
      ]);

  /// Baris warna: [bawaan] + preset + [kustom RGB] (editor muncul inline).
  Widget _colorRow(IslandTheme t, AppLocalizations l10n,
      {required _ColorTarget target,
      required Color? current,
      required List<Color> presets,
      required Future<void> Function(Color?) onPick}) {
    final isPreset = current != null && presets.any((c) => c.toARGB32() == current.toARGB32());
    final open = _editing == target;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        _swatch(const Icon(Icons.auto_awesome, size: 13, color: Colors.white70),
            null, current == null, () => onPick(null)),
        for (final c in presets)
          _swatch(const SizedBox.shrink(), c,
              current != null && current.toARGB32() == c.toARGB32(), () => onPick(c)),
        _swatch(
          const Icon(Icons.colorize, size: 13, color: Colors.white70),
          (current != null && !isPreset) ? current : null,
          open || (current != null && !isPreset),
          () => setState(() => _editing = open ? null : target),
        ),
      ]),
      if (open)
        _ColorEditor(
          initial: current ?? t.accentColor,
          t: t,
          l10n: l10n,
          onCancel: () => setState(() => _editing = null),
          onApply: (c) {
            onPick(c);
            setState(() => _editing = null);
          },
        ),
    ]);
  }

  Widget _label(String text, IslandTheme t) => Text(
        text,
        style: t.titleStyle.copyWith(fontSize: 11, color: Colors.white54),
      );

  Widget _chip(String label, bool active, VoidCallback onTap, IslandTheme t) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: active ? Colors.white38 : Colors.transparent,
                width: 0.8),
          ),
          child: Text(label,
              style: TextStyle(
                  color: active ? Colors.white : Colors.white54, fontSize: 11)),
        ),
      );

  String _styleLabel(VisualStyle v) => const {
        VisualStyle.ios17: 'iOS 17',
        VisualStyle.macosNotch: 'macOS Notch',
        VisualStyle.materialYou: 'Material You',
        VisualStyle.customGaming: 'Gaming',
      }[v]!;

  String _posLabel(IslandPosition p) => const {
        IslandPosition.topCenter: 'Top Center',
        IslandPosition.topRight: 'Top Right',
        IslandPosition.bottomCenter: 'Bottom Center',
        IslandPosition.followNotch: 'Follow Notch',
      }[p]!;

  String _vizLabel(VisualizerMode m) => const {
        VisualizerMode.bars: 'Bars',
        VisualizerMode.circularWave: 'Circular',
        VisualizerMode.particleSystem: 'Particles',
        VisualizerMode.adaptive: 'Adaptive',
      }[m]!;
}

enum _ColorTarget { accent, background }

class _ColorEditor extends StatefulWidget {
  const _ColorEditor(
      {required this.initial,
      required this.t,
      required this.l10n,
      required this.onApply,
      required this.onCancel});
  final Color initial;
  final IslandTheme t;
  final AppLocalizations l10n;
  final ValueChanged<Color> onApply;
  final VoidCallback onCancel;

  @override
  State<_ColorEditor> createState() => _ColorEditorState();
}

class _ColorEditorState extends State<_ColorEditor> {
  late double _r, _g, _b;

  @override
  void initState() {
    super.initState();
    final v = widget.initial.toARGB32();
    _r = ((v >> 16) & 0xFF).toDouble();
    _g = ((v >> 8) & 0xFF).toDouble();
    _b = (v & 0xFF).toDouble();
  }

  Color get _color => Color.fromARGB(255, _r.round(), _g.round(), _b.round());

  Widget _slider(String name, double v, Color c, ValueChanged<double> on) =>
      Row(children: [
        SizedBox(
            width: 14,
            child: Text(name,
                style: widget.t.subtitleStyle.copyWith(fontSize: 11))),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
                activeTrackColor: c, thumbColor: c, trackHeight: 3),
            child: Slider(value: v, min: 0, max: 255, onChanged: on),
          ),
        ),
        SizedBox(
            width: 28,
            child: Text(v.round().toString(),
                style: widget.t.subtitleStyle.copyWith(fontSize: 10))),
      ]);

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(widget.l10n.customColor,
            style: t.subtitleStyle.copyWith(letterSpacing: 1)),
        const SizedBox(height: 8),
        Container(
          height: 30,
          decoration: BoxDecoration(
            color: _color,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white24),
          ),
        ),
        const SizedBox(height: 4),
        _slider('R', _r, Colors.redAccent, (v) => setState(() => _r = v)),
        _slider('G', _g, Colors.greenAccent, (v) => setState(() => _g = v)),
        _slider('B', _b, Colors.lightBlueAccent, (v) => setState(() => _b = v)),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
              onPressed: widget.onCancel, child: Text(widget.l10n.cancel)),
          TextButton(
            onPressed: () => widget.onApply(_color),
            child: Text(widget.l10n.save,
                style: TextStyle(
                    color: t.accentColor, fontWeight: FontWeight.w600)),
          ),
        ]),
      ]),
    );
  }
}
