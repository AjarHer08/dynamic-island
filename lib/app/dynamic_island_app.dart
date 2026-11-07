import 'dart:async';
import 'dart:io' show Platform, exit;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/alarm_provider.dart';
import '../providers/battery_provider.dart';
import '../providers/dnd_provider.dart';
import '../providers/music_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/wellness_provider.dart';
import '../services/notification_listener_service.dart';
import '../services/reply_bridge.dart';
import '../services/auto_hide_service.dart';
import '../services/update_service.dart';
import '../services/sound_service.dart';
import '../widgets/live_clock.dart';
import '../widgets/liquid_glass.dart';
import '../theme/island_theme.dart';
import '../providers/lyrics_provider.dart';
import '../widgets/panels/battery_panel.dart';
import '../widgets/panels/calendar_panel.dart';
import '../widgets/panels/lyrics_panel.dart';
import '../widgets/panels/music_panel.dart';
import '../widgets/panels/notification_panel.dart';
import '../widgets/panels/performance_panel.dart';
import '../widgets/panels/reminder_dnd_panel.dart';
import '../widgets/panels/settings_panel.dart';
import '../widgets/panels/weather_alarm_panel.dart';
import '../widgets/visualizers/adaptive_visualizer.dart';

enum _Tab {
  music,
  lyrics,
  notifications,
  weatherAlarm,
  calendar,
  reminderDnd,
  battery,
  performance,
  settings,
}

/// Mouse & touchpad juga bisa menggeser halaman (secara bawaan hanya sentuhan).
class _DragScrollBehavior extends MaterialScrollBehavior {
  const _DragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class DynamicIslandApp extends StatefulWidget {
  const DynamicIslandApp({super.key});

  @override
  State<DynamicIslandApp> createState() => _DynamicIslandAppState();
}

class _DynamicIslandAppState extends State<DynamicIslandApp>
    with SingleTickerProviderStateMixin, WindowListener, TrayListener {
  bool _expanded = false;
  _Tab _tab = _Tab.music;
  late final AnimationController _anim;
  late Animation<double> _sizeAnim;
  PageController? _pc; // dibuat ulang tiap island dibuka
  Size? _appliedBig; // ukuran window terakhir yang diterapkan saat terbuka
  bool _resizing = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    trayManager.addListener(this);
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    _sizeAnim = CurvedAnimation(parent: _anim, curve: Curves.easeInOutCubic);

    WidgetsBinding.instance.addPostFrameCallback((_) => _wire());
  }

  final _notifService = NotificationListenerService();

  bool get _isId => Localizations.localeOf(context).languageCode == 'id';

  /// Menyambungkan alarm, pengingat, dan notifikasi desktop ke island.
  void _wire() {
    final notif = context.read<NotificationProvider>();
    final dnd = context.read<DndProvider>()..load();
    final alarms = context.read<AlarmProvider>();
    context.read<LyricsProvider>().bind(context.read<MusicProvider>());
    final well = context.read<WellnessProvider>();

    ReplyBridge.start(); // jembatan ke ekstensi WA Web

    // Pembaruan + sembunyi otomatis.
    final settings = context.read<SettingsProvider>();
    final music = context.read<MusicProvider>();
    context.read<UpdateService>().start(() => settings.autoUpdate);
    final ah = AutoHideService.instance;
    ah.idleEnabled = () => settings.autoHideIdle;
    ah.idleSeconds = () => settings.idleSeconds;
    ah.videoEnabled = () => settings.hideOnVideo;
    ah.isVideoPlaying = () => music.isVideoPlaying;
    ah.isActive = () =>
        _expanded ||
        notif.active != null ||
        alarms.ringing != null;
    ah.isUrgent = () => alarms.ringing != null;
    ah.start();

    // Alarm: selalu berbunyi, bahkan saat DND.
    alarms.onAlarmFired = (a) {
      if (!mounted) return;
      final label = a.label.isEmpty ? 'Alarm' : a.label;
      notif.push(
        sender: _isId ? 'Alarm berbunyi' : 'Alarm ringing',
        body: '${twoDigits(a.hour)}:${twoDigits(a.minute)}  $label',
        app: 'Alarm',
        kind: NotifKind.alarm,
        showFor: const Duration(seconds: 40),
      );
      SoundService.startAlarm();
    };

    // Istirahat & minum: dilewati saat DND.
    well.isDnd = () => dnd.enabled;
    well.onDue = (item) {
      if (!mounted) return;
      final id = _isId;
      if (item.key == 'rest') {
        notif.push(
          sender: id ? 'Waktunya istirahat' : 'Time for a break',
          body: id
              ? 'Sudah ${item.minutes} menit. Berdiri, regangkan badan, istirahatkan mata.'
              : '${item.minutes} minutes passed. Stand up, stretch, rest your eyes.',
          app: id ? 'Istirahat' : 'Break',
          kind: NotifKind.rest,
          showFor: const Duration(seconds: 12),
        );
      } else {
        notif.push(
          sender: id ? 'Waktunya minum' : 'Time to drink',
          body: id ? 'Minum segelas air putih.' : 'Have a glass of water.',
          app: id ? 'Minum' : 'Water',
          kind: NotifKind.water,
          showFor: const Duration(seconds: 12),
        );
      }
      SoundService.chime();
    };

    // Notifikasi desktop asli (WhatsApp, Telegram, email, dll).
    _notifService.start((app, summary, body) {
      if (!mounted) return;
      final a = app.toLowerCase();
      if (a.contains('spotify') || a.contains('dynamic')) return;
      if (summary.isEmpty && body.isEmpty) return;
      final clean = body.replaceAll(RegExp(r'<[^>]*>'), '').trim();
      notif.push(
        sender: summary.isEmpty ? app : summary,
        body: clean,
        app: app,
        silent: dnd.enabled,
      );
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    _notifService.stop();
    SoundService.stop();
    _anim.dispose();
    _pc?.dispose();
    super.dispose();
  }

  bool _busy = false;

  /// Tap pill: tutup popup/alarm yang aktif lalu buka panel yang relevan.
  void _onPillTap() {
    final notif = context.read<NotificationProvider>();
    final n = notif.active;
    if (n != null) {
      notif.dismiss();
      SoundService.stop();
      context.read<AlarmProvider>().stopRinging();
      if (n.kind == NotifKind.message) notif.requestReply(n.id);
      _tab = switch (n.kind) {
        NotifKind.message => _Tab.notifications,
        NotifKind.alarm => _Tab.weatherAlarm,
        NotifKind.rest || NotifKind.water => _Tab.reminderDnd,
      };
    }
    _toggle();
  }

  Future<void> _toggle() async {
    if (_busy) return;
    _busy = true;
    try {
      final s = context.read<SettingsProvider>();
      final t = s.theme;
      final big = Size(t.expandedWidth, t.expandedHeight);

      if (!_expanded) {
        _pc?.dispose();
        _pc = PageController(initialPage: _tab.index);
        context.read<BatteryProvider>().refresh();
      }

      setState(() => _expanded = !_expanded);
      if (_expanded) {
        _appliedBig = big;
        // Besarkan window dulu, baru animasi.
        await windowManager.setSize(big);
        await s.reposition(size: big);
        await windowManager.focus(); // supaya blur (klik di luar) terdeteksi
        if (mounted) _anim.forward();
      } else {
        _appliedBig = null;
        // Animasi mengecil dulu, baru kecilkan window. Ukuran pill dibaca
        // ulang karena pengguna bisa mengubahnya saat panel terbuka.
        await _anim.reverse();
        final t2 = s.theme;
        final pill = Size(t2.pillWidth, t2.pillHeight);
        await windowManager.setSize(pill);
        await s.reposition(size: pill);
      }
    } finally {
      _busy = false;
    }
  }

  /// Pengguna mengubah ukuran panel lewat Settings saat panel terbuka:
  /// samakan ukuran window dengan ukuran baru.
  Future<void> _syncExpandedWindow() async {
    if (_resizing) return;
    _resizing = true;
    try {
      final s = context.read<SettingsProvider>();
      while (mounted && _expanded && !_busy) {
        final t = s.theme;
        final big = Size(t.expandedWidth, t.expandedHeight);
        if (_appliedBig == big) break;
        _appliedBig = big;
        try {
          await windowManager.setSize(big);
          await s.reposition(size: big);
        } catch (_) {}
      }
    } finally {
      _resizing = false;
    }
  }

  void _goTo(_Tab tab) {
    setState(() => _tab = tab);
    final pc = _pc;
    if (pc == null || !pc.hasClients) return;
    final cur = (pc.page ?? tab.index.toDouble()).round();
    if ((cur - tab.index).abs() > 1) {
      pc.jumpToPage(tab.index);
    } else {
      pc.animateToPage(tab.index,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic);
    }
  }

  // ---------------------------------------------------------- System tray

  @override
  void onTrayIconMouseDown() {
    if (Platform.isWindows) _showFromTray();
  }

  @override
  void onTrayIconRightMouseDown() {
    // Windows: menu harus dimunculkan manual. Linux menampilkannya sendiri.
    if (Platform.isWindows) trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _showFromTray();
      case 'dnd':
        context.read<DndProvider>().toggle();
      case 'exit':
        _quit();
    }
  }

  Future<void> _showFromTray() async {
    try {
      await AutoHideService.instance.wake();
      if (!_expanded) {
        await _toggle();
      } else {
        await windowManager.focus();
      }
    } catch (_) {}
  }

  bool _quitting = false;

  /// Keluar total dari aplikasi (menu tray -> Exit).
  Future<void> _quit() async {
    if (_quitting) return;
    _quitting = true;
    // Hentikan semua yang masih berjalan; tiap langkah dibungkus try/catch
    // dan diberi batas waktu supaya Exit tidak pernah macet.
    Future<void> step(Future<void> Function() f) async {
      try {
        await f().timeout(const Duration(milliseconds: 800));
      } catch (_) {}
    }

    AutoHideService.instance.dispose();
    await step(() async => SoundService.stop());
    await step(() async => _notifService.stop());
    await step(() async => context.read<MusicProvider>().dispose()); // hentikan parec
    await step(() => trayManager.destroy());
    await step(() => windowManager.setPreventClose(false));
    await step(() => windowManager.destroy());
    exit(0); // pastikan proses benar-benar berhenti
  }

  // Klik di luar island -> window kehilangan fokus -> tutup otomatis.
  @override
  void onWindowBlur() {
    if (_expanded && !_busy) _toggle();
  }

  @override
  void onWindowResize() {}
  @override
  void onWindowMoved() {}
  @override
  void onWindowFocus() {}
  @override
  void onWindowClose() {}
  @override
  void onWindowEvent(String eventName) {}

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>();
    final music = context.watch<MusicProvider>();
    final notif = context.watch<NotificationProvider>();
    final t = s.theme;

    if (_expanded &&
        !_busy &&
        _appliedBig != Size(t.expandedWidth, t.expandedHeight)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncExpandedWindow();
      });
    }

    return Material(
      color: Colors.transparent,
      child: AnimatedBuilder(
        animation: _sizeAnim,
        builder: (_, __) {
          final w = _lerp(t.pillWidth, t.expandedWidth, _sizeAnim.value);
          final h = _lerp(t.pillHeight, t.expandedHeight, _sizeAnim.value);
          final r = _lerp(t.borderRadius, t.expandedRadius, _sizeAnim.value);
          final content = _expanded
              ? OverflowBox(
                  alignment: Alignment.topCenter,
                  minWidth: t.expandedWidth,
                  maxWidth: t.expandedWidth,
                  minHeight: t.expandedHeight,
                  maxHeight: t.expandedHeight,
                  child: _expandedView(t),
                )
              : GestureDetector(
                  onTap: _onPillTap,
                  behavior: HitTestBehavior.opaque,
                  child: _pillView(t, music, notif, s.vizMode),
                );

          if (t.glass) {
            return Center(
              child: SizedBox(
                width: w,
                height: h,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(r),
                  child: CustomPaint(
                    painter: LiquidGlassPainter(
                      radius: r,
                      tint: Color.lerp(
                          t.pillColor, t.expandedColor, _sizeAnim.value)!,
                      opacity: s.opacity,
                      accent: t.accentColor,
                    ),
                    child: content,
                  ),
                ),
              ),
            );
          }

          return Center(
            child: Container(
              width: w,
              height: h,
              decoration: BoxDecoration(
                color: t.pillColor.withValues(alpha: s.opacity),
                // Tanpa boxShadow: window sama besar dengan island, jadi bayangan
                // terpotong jadi kotak hitam di sekeliling pill.
                borderRadius: BorderRadius.circular(r),
              ),
              clipBehavior: Clip.antiAlias,
              child: content,
            ),
          );
        },
      ),
    );
  }

  /// Pill kecil: mini-visualizer kiri + jam & status dot kanan.
  Widget _pillView(IslandTheme t, MusicProvider music,
      NotificationProvider notif, VisualizerMode vizMode) {
    final hasNotif = notif.active != null;
    return Stack(
      alignment: Alignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            SizedBox(
              width: 44,
              height: 26,
              child: hasNotif
                  ? Icon(notif.active!.kind.icon,
                      color: notif.active!.kind.color, size: 14)
                  : AdaptiveVisualizer(
                      spectrum: music.spectrum,
                      color: t.accentColor,
                      mode: vizMode, // ikut pilihan di Settings
                    ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: music.isPlaying ? t.accentColor : Colors.white24,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(height: 3),
                const LiveClock(
                    style: TextStyle(color: Colors.white54, fontSize: 9)),
              ],
            ),
            _pillBattery(t),
          ],
        ),
        if (hasNotif)
          Positioned.fill(
            child: Container(
              color: t.pillColor.withValues(alpha: 0.88),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                CircleAvatar(
                    radius: 10,
                    backgroundColor: notif.active!.kind.color,
                    child: Icon(notif.active!.kind.icon,
                        size: 10, color: Colors.white)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${notif.active!.sender}: ${notif.active!.body}',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
          ),
      ],
    );
  }

  /// Baterai laptop di pill (saat island menutup). Hilang bila tidak ada baterai.
  Widget _pillBattery(IslandTheme t) {
    return Consumer<BatteryProvider>(builder: (_, b, __) {
      final lap = b.laptop;
      if (lap == null) return const SizedBox.shrink();
      final chg = lap.state == PowerState.charging;
      final color = batteryColor(lap.percent, chg, t);
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(batteryIcon(lap.percent, chg), size: 13, color: color),
          const SizedBox(width: 1),
          Text('${lap.percent}%',
              style: TextStyle(
                  color: color, fontSize: 9, fontWeight: FontWeight.w600)),
        ]),
      );
    });
  }

  /// Panel expanded: tab bar + halaman yang bisa digeser kiri/kanan.
  Widget _expandedView(IslandTheme t) => Column(children: [
        Container(
          height: 38,
          color: t.glass ? Colors.white.withValues(alpha: 0.04) : t.expandedColor,
          child: Row(children: [
            const SizedBox(width: 6),
            Expanded(
              child: Row(children: [
                for (final tab in _Tab.values)
                  Expanded(child: _tabButton(tab, t)),
              ]),
            ),
            Consumer<BatteryProvider>(builder: (_, b, __) {
              final lap = b.laptop;
              if (lap == null) return const SizedBox(width: 4);
              final chg = lap.state == PowerState.charging;
              final color = batteryColor(lap.percent, chg, t);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _goTo(_Tab.battery),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(batteryIcon(lap.percent, chg), size: 14, color: color),
                    const SizedBox(width: 2),
                    Text('${lap.percent}%',
                        style: TextStyle(color: color, fontSize: 10)),
                  ]),
                ),
              );
            }),
            GestureDetector(
              onTap: _toggle,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.keyboard_arrow_up,
                    color: Colors.white54, size: 18),
              ),
            ),
          ]),
        ),
        const Divider(height: 1, color: Colors.white10),
        Expanded(
          child: Container(
            color: t.glass ? Colors.transparent : t.expandedColor,
            child: ScrollConfiguration(
              behavior: const _DragScrollBehavior(),
              child: PageView.builder(
                controller: _pc,
                itemCount: _Tab.values.length,
                onPageChanged: (i) => setState(() => _tab = _Tab.values[i]),
                itemBuilder: (_, i) => _panelFor(_Tab.values[i]),
              ),
            ),
          ),
        ),
      ]);

  Widget _tabButton(_Tab tab, IslandTheme t) {
    final active = _tab == tab;
    const icons = {
      _Tab.music: Icons.music_note,
      _Tab.lyrics: Icons.lyrics,
      _Tab.notifications: Icons.notifications,
      _Tab.weatherAlarm: Icons.wb_sunny,
      _Tab.calendar: Icons.calendar_month,
      _Tab.reminderDnd: Icons.event_note,
      _Tab.battery: Icons.battery_full,
      _Tab.performance: Icons.speed,
      _Tab.settings: Icons.settings,
    };
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _goTo(tab),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 1),
        decoration: BoxDecoration(
          color: active ? t.accentColor.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Icon(icons[tab],
              size: 15, color: active ? t.accentColor : Colors.white38),
        ),
      ),
    );
  }

  Widget _panelFor(_Tab tab) => switch (tab) {
        _Tab.music => const MusicPanel(),
        _Tab.lyrics => const LyricsPanel(),
        _Tab.notifications => const NotificationPanel(),
        _Tab.weatherAlarm => const WeatherAlarmPanel(),
        _Tab.calendar => const CalendarPanel(),
        _Tab.reminderDnd => const ReminderDndPanel(),
        _Tab.battery => const BatteryPanel(),
        _Tab.performance => const PerformancePanel(),
        _Tab.settings => const SettingsPanel(),
      };

  double _lerp(double a, double b, double t) => a + (b - a) * t;
}
