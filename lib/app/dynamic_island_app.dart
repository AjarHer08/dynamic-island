import 'dart:async';
import 'dart:io' show Platform, exit;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/alarm_provider.dart';
import '../providers/battery_provider.dart';
import '../providers/call_provider.dart';
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
import '../widgets/message_banner.dart';
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
import '../widgets/panels/tasks_panel.dart';
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
  tasks,
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
    with TickerProviderStateMixin, WindowListener, TrayListener {
  bool _expanded = false;
  _Tab _tab = _Tab.music;
  late final AnimationController _anim;
  late Animation<double> _sizeAnim;
  PageController? _pc; // dibuat ulang tiap island dibuka
  Size? _appliedBig; // ukuran window terakhir yang diterapkan saat terbuka
  bool _resizing = false;

  // ---- panggilan masuk ----
  static const _kCallSize = Size(380, 78);
  static const _kMsgSize = Size(400, 120); // pesan baru + kolom balas
  late final AnimationController _callAnim;
  CallProvider? _calls;
  NotificationProvider? _notifP;
  Size? _bannerSize; // ukuran window banner yang sedang dipakai (null = tidak ada)
  bool _callBusy = false, _callPending = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    trayManager.addListener(this);
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    _sizeAnim = CurvedAnimation(parent: _anim, curve: Curves.easeInOutCubic);
    _callAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 240));

    WidgetsBinding.instance.addPostFrameCallback((_) => _wire());
  }

  final _notifService = NotificationListenerService();

  bool get _isId => Localizations.localeOf(context).languageCode == 'id';

  /// Menyambungkan alarm, pengingat, dan notifikasi desktop ke island.
  void _wire() {
    final notif = context.read<NotificationProvider>();
    final dnd = context.read<DndProvider>()..load();
    final alarms = context.read<AlarmProvider>();

    // Panggilan masuk: dari ekstensi WA Bridge dan dari notifikasi desktop.
    final calls = context.read<CallProvider>();
    _calls = calls..addListener(_onBannerChanged);
    _notifP = notif..addListener(_onBannerChanged);
    calls.onLog = (caller, app, event) {
      if (!mounted) return;
      final id = _isId;
      final text = switch (event) {
        'accepted' => id ? 'Panggilan dijawab' : 'Call answered',
        'rejected' => id ? 'Panggilan ditolak' : 'Call declined',
        'ended' => id ? 'Panggilan masuk berakhir' : 'Incoming call ended',
        'incoming' => id ? 'Panggilan masuk (DND)' : 'Incoming call (DND)',
        _ => id ? 'Panggilan disembunyikan' : 'Call dismissed',
      };
      notif.push(sender: caller, body: text, app: app, silent: true);
    };
    ReplyBridge.onEvent = (m) {
      if (m['type'] != 'wa-call') return;
      if (m['state'] == 'incoming') {
        calls.onIncoming(
          caller: (m['name'] ?? '').toString(),
          app: 'WhatsApp',
          video: m['video'] == true,
          bridge: true,
          silent: dnd.enabled,
        );
      } else if (m['state'] == 'ended') {
        calls.onEnded();
      }
    };
    context.read<LyricsProvider>()
      ..bindSettings(context.read<SettingsProvider>())
      ..bind(context.read<MusicProvider>());
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
        alarms.ringing != null ||
        calls.call != null;
    ah.isUrgent = () => alarms.ringing != null || calls.call != null;
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
      if (CallProvider.looksLikeCall(summary, clean)) {
        calls.onIncoming(
          caller: CallProvider.callerFrom(app, summary, clean),
          app: app,
          video: CallProvider.looksLikeVideo(summary, clean),
          silent: dnd.enabled,
        );
        return;
      }
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
    _calls?.removeListener(_onBannerChanged);
    _notifP?.removeListener(_onBannerChanged);
    ReplyBridge.onEvent = null;
    _callAnim.dispose();
    _anim.dispose();
    _pc?.dispose();
    super.dispose();
  }

  bool _busy = false;

  /// Ukuran banner yang dibutuhkan sekarang: panggilan masuk, atau pesan baru
  /// (dengan kolom balas). null = cukup pill biasa, atau panel penuh terbuka
  /// (banner panggilan tampil sebagai overlay di panel).
  Size? _bannerTarget() {
    if (_expanded) return null;
    if (_calls?.call != null) return _kCallSize;
    final a = _notifP?.active;
    if (a != null && a.kind == NotifKind.message) return _kMsgSize;
    return null;
  }

  void _onBannerChanged() {
    if (!mounted) return;
    if (_bannerTarget() == _bannerSize) return;
    _syncBanner();
  }

  /// Jalankan animasi banner tanpa pernah menggantung bila animasi dibatalkan.
  Future<void> _runBannerAnim(bool forward) async {
    try {
      await (forward ? _callAnim.forward() : _callAnim.reverse())
          .orCancel
          .timeout(const Duration(milliseconds: 800));
    } catch (_) {}
  }

  /// Besarkan window ke ukuran banner, kecilkan lagi setelah selesai.
  Future<void> _syncBanner() async {
    if (_callBusy) {
      _callPending = true;
      return;
    }
    _callBusy = true;
    try {
      final s = context.read<SettingsProvider>();
      for (var i = 0; i < 4 && mounted; i++) {
        final target = _bannerTarget();
        if (target == _bannerSize) break;
        if (target != null) {
          setState(() => _bannerSize = target);
          await windowManager.setSize(target);
          await s.reposition(size: target);
          await _runBannerAnim(true);
        } else {
          await _runBannerAnim(false);
          if (!mounted) break;
          setState(() => _bannerSize = null);
          if (!_expanded && !_busy && _bannerTarget() == null) {
            final t = s.theme;
            final pill = Size(t.pillWidth, t.pillHeight);
            await windowManager.setSize(pill);
            await s.reposition(size: pill);
          }
        }
      }
    } catch (_) {
    } finally {
      _callBusy = false;
      if (_callPending && mounted) {
        _callPending = false;
        _onBannerChanged();
      }
    }
  }

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
        _bannerSize = null; // panel penuh menggantikan ukuran banner
        _callAnim.value = 0;
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
        _revealTab();
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
      _onBannerChanged(); // ada panggilan yang masih berdering?
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
    final callP = context.watch<CallProvider>();
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
        animation: Listenable.merge([_sizeAnim, _callAnim]),
        builder: (_, __) {
          var w = _lerp(t.pillWidth, t.expandedWidth, _sizeAnim.value);
          var h = _lerp(t.pillHeight, t.expandedHeight, _sizeAnim.value);
          var r = _lerp(t.borderRadius, t.expandedRadius, _sizeAnim.value);
          final activeN = notif.active;
          final showCall = callP.call != null && !_expanded;
          final showMsg = !_expanded &&
              !showCall &&
              activeN != null &&
              activeN.kind == NotifKind.message;
          final bs = _bannerSize ?? (showMsg ? _kMsgSize : _kCallSize);
          final cm = _expanded ? 0.0 : _callAnim.value;
          if (cm > 0) {
            w = _lerp(t.pillWidth, bs.width, cm);
            h = _lerp(t.pillHeight, bs.height, cm);
            r = _lerp(t.borderRadius, showMsg ? 22.0 : bs.height / 2.4, cm);
          }
          final content = showCall
              ? OverflowBox(
                  alignment: Alignment.center,
                  minWidth: _kCallSize.width,
                  maxWidth: _kCallSize.width,
                  minHeight: _kCallSize.height,
                  maxHeight: _kCallSize.height,
                  child: _callBanner(t, callP, overlay: false),
                )
              : showMsg
              ? OverflowBox(
                  alignment: Alignment.center,
                  minWidth: _kMsgSize.width,
                  maxWidth: _kMsgSize.width,
                  minHeight: _kMsgSize.height,
                  maxHeight: _kMsgSize.height,
                  child: MessageBanner(
                      key: ValueKey(activeN.id),
                      n: activeN,
                      t: t,
                      onOpen: _onPillTap),
                )
              : _expanded
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
                    foregroundPainter: t.hud
                        ? HudFramePainter(
                            color: t.accentColor,
                            visible: (_sizeAnim.value - 0.6) / 0.4)
                        : null,
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
                border: Border.all(
                    color: t.accentColor.withValues(alpha: 0.35), width: 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: t.hud
                  ? CustomPaint(
                      foregroundPainter: HudFramePainter(
                          color: t.accentColor,
                          visible: (_sizeAnim.value - 0.6) / 0.4),
                      child: content)
                  : content,
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
              width: 58,
              height: 26,
              child: hasNotif
                  ? Icon(notif.active!.kind.icon,
                      color: notif.active!.kind.color, size: 15)
                  : AdaptiveVisualizer(
                      spectrum: music.spectrum,
                      color: t.accentColor,
                      mode: vizMode, // ikut pilihan di Settings
                    ),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: music.isPlaying ? t.accentColor : t.accentColor.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                  boxShadow: music.isPlaying
                      ? [BoxShadow(color: t.accentColor.withValues(alpha: 0.7), blurRadius: 6)]
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              const LiveClock(
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ]),
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

  /// Baterai laptop di pill (saat island menutup): persen + ikon baterai.
  /// Hilang bila tidak ada baterai.
  Widget _pillBattery(IslandTheme t) {
    return Consumer<BatteryProvider>(builder: (_, b, __) {
      final lap = b.laptop;
      if (lap == null) return const SizedBox.shrink();
      final chg = lap.state == PowerState.charging;
      final low = lap.percent <= 20 && !chg;
      final fill = low
          ? const Color(0xFFFF453A)
          : (chg ? const Color(0xFF30D158) : Colors.white);
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${lap.percent}%',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
          const SizedBox(width: 6),
          _BatteryGlyph(percent: lap.percent, color: fill),
        ]),
      );
    });
  }

  final _tabKeys = {for (final tab in _Tab.values) tab: GlobalKey()};

  /// Geser strip tab supaya tab aktif selalu terlihat.
  void _revealTab() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _tabKeys[_tab]?.currentContext;
      if (c == null) return;
      Scrollable.ensureVisible(c,
          alignment: 0.5,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic);
    });
  }

  /// Panel expanded: strip tab teks + halaman yang bisa digeser kiri/kanan.
  Widget _expandedView(IslandTheme t) => Stack(fit: StackFit.expand, children: [
        _expandedBody(t),
        Consumer<CallProvider>(
          builder: (_, cp, __) => cp.call == null
              ? const SizedBox.shrink()
              : Positioned(
                  top: 8,
                  left: 10,
                  right: 10,
                  height: 72,
                  child: _callBanner(t, cp, overlay: true),
                ),
        ),
      ]);

  Widget _expandedBody(IslandTheme t) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 8, 6),
          child: Container(
            height: 34,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Row(children: [
              Expanded(
                child: ScrollConfiguration(
                  behavior: const _DragScrollBehavior(),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(children: [
                      for (final tab in _Tab.values) _tabButton(tab, t),
                    ]),
                  ),
                ),
              ),
              GestureDetector(
                onTap: _toggle,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.keyboard_arrow_up,
                      color: Colors.white54, size: 18),
                ),
              ),
            ]),
          ),
        ),
        Expanded(
          child: Container(
            color: t.glass ? Colors.transparent : t.expandedColor,
            child: ScrollConfiguration(
              behavior: const _DragScrollBehavior(),
              child: PageView.builder(
                controller: _pc,
                itemCount: _Tab.values.length,
                onPageChanged: (i) {
                  setState(() => _tab = _Tab.values[i]);
                  _revealTab();
                },
                itemBuilder: (_, i) => _panelFor(_Tab.values[i]),
              ),
            ),
          ),
        ),
      ]);

  String _tabLabel(_Tab tab) {
    final id = _isId;
    return switch (tab) {
      _Tab.music => id ? 'musik' : 'music',
      _Tab.lyrics => id ? 'lirik' : 'lyrics',
      _Tab.notifications => id ? 'notifikasi' : 'notifications',
      _Tab.weatherAlarm => id ? 'cuaca' : 'weather',
      _Tab.calendar => id ? 'kalender' : 'calendar',
      _Tab.reminderDnd => id ? 'pengingat' : 'reminders',
      _Tab.tasks => id ? 'tugas' : 'tasks',
      _Tab.battery => id ? 'baterai' : 'battery',
      _Tab.performance => id ? 'performa' : 'performance',
      _Tab.settings => id ? 'pengaturan' : 'settings',
    };
  }

  Widget _tabButton(_Tab tab, IslandTheme t) {
    final active = _tab == tab;
    return GestureDetector(
      key: _tabKeys[tab],
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _goTo(tab);
        _revealTab();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? t.chipFill : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          _tabLabel(tab),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? Colors.white : Colors.white60,
          ),
        ),
      ),
    );
  }

  String _callNote(String note) {
    final id = _isId;
    return switch (note) {
      'answered' => id ? 'Dijawab' : 'Answered',
      'opened' =>
        id ? 'Aplikasi dibuka, jawab di sana' : 'App opened, answer there',
      'unsupported' =>
        id ? 'Buka aplikasinya untuk menjawab' : 'Open the app to answer',
      'rejected' => id ? 'Ditolak' : 'Declined',
      'dismissed' => id
          ? 'Disembunyikan; aplikasi mungkin masih berdering'
          : 'Hidden; the app may keep ringing',
      _ => note,
    };
  }

  /// Banner panggilan masuk: nama penelepon + tombol Tolak (merah) dan
  /// Terima (hijau). [overlay] = tampil di atas panel yang sedang terbuka.
  Widget _callBanner(IslandTheme t, CallProvider cp, {required bool overlay}) {
    final c = cp.call;
    if (c == null) return const SizedBox.shrink();
    final id = _isId;
    final ringing = cp.phase == CallPhase.ringing;
    final kind = c.video
        ? (id ? 'Panggilan video' : 'Video call')
        : (id ? 'Panggilan suara' : 'Voice call');
    final sub = ringing ? '$kind  ·  ${c.app}' : _callNote(cp.note);
    final initial =
        c.caller.isEmpty ? '?' : String.fromCharCode(c.caller.runes.first).toUpperCase();
    final isWa = c.app.toLowerCase().contains('whatsapp');
    const red = Color(0xFFFF453A), green = Color(0xFF30D158);

    Widget circle(Color color, IconData icon, VoidCallback? onTap, String tip,
        {bool spin = false}) {
      return Tooltip(
        message: tip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 10)
              ],
            ),
            child: spin
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      );
    }

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: isWa ? const Color(0xFF25D366) : t.chipFill,
          child: Text(initial,
              style: const TextStyle(
                  color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.caller,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: ringing ? Colors.white70 : t.accentColor,
                      fontSize: 11.5,
                      height: 1.25)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        if (ringing) ...[
          circle(red, Icons.call_end, cp.busy ? null : cp.reject,
              id ? 'Tolak panggilan' : 'Decline call'),
          const SizedBox(width: 12),
          circle(green, c.video ? Icons.videocam : Icons.call,
              cp.busy ? null : cp.accept,
              id ? 'Terima panggilan' : 'Accept call',
              spin: cp.busy),
        ] else
          Icon(
              cp.phase == CallPhase.answered ? Icons.check_circle : Icons.call_end,
              color: cp.phase == CallPhase.answered ? green : red,
              size: 28),
      ]),
    );

    if (!overlay) return row;
    return Container(
      decoration: BoxDecoration(
        color: t.expandedColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.accentColor.withValues(alpha: 0.5)),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12)],
      ),
      child: row,
    );
  }

  Widget _panelFor(_Tab tab) => switch (tab) {
        _Tab.music => const MusicPanel(),
        _Tab.lyrics => const LyricsPanel(),
        _Tab.notifications => const NotificationPanel(),
        _Tab.weatherAlarm => const WeatherAlarmPanel(),
        _Tab.calendar => const CalendarPanel(),
        _Tab.reminderDnd => const ReminderDndPanel(),
        _Tab.tasks => const TasksPanel(),
        _Tab.battery => const BatteryPanel(),
        _Tab.performance => const PerformancePanel(),
        _Tab.settings => const SettingsPanel(),
      };

  double _lerp(double a, double b, double t) => a + (b - a) * t;
}


/// Ikon baterai bergaya gambar referensi: kotak bergaris, isi sesuai persen,
/// dan kepala kecil di kanan.
class _BatteryGlyph extends StatelessWidget {
  const _BatteryGlyph({required this.percent, required this.color});
  final int percent;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(26, 13), painter: _BatteryPainter(percent, color));
}

class _BatteryPainter extends CustomPainter {
  _BatteryPainter(this.percent, this.color);
  final int percent;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final body = Rect.fromLTWH(0.7, 0.7, size.width - 4, size.height - 1.4);
    canvas.drawRRect(
        RRect.fromRectAndRadius(body, const Radius.circular(3.5)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = color.withValues(alpha: 0.85));
    final inner = body.deflate(2.2);
    final w = inner.width * (percent.clamp(0, 100) / 100);
    if (w > 0) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(inner.left, inner.top, w, inner.height),
              const Radius.circular(1.6)),
          Paint()..color = color);
    }
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(size.width - 2.6, size.height / 2 - 2.6, 2.4, 5.2),
            const Radius.circular(1.2)),
        Paint()..color = color.withValues(alpha: 0.85));
  }

  @override
  bool shouldRepaint(covariant _BatteryPainter old) =>
      old.percent != percent || old.color != color;
}
