import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

import 'l10n/app_localizations.dart';
import 'providers/settings_provider.dart';
import 'providers/music_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/weather_provider.dart';
import 'providers/alarm_provider.dart';
import 'providers/dnd_provider.dart';
import 'providers/lyrics_provider.dart';
import 'providers/wellness_provider.dart';
import 'providers/battery_provider.dart';
import 'providers/performance_provider.dart';
import 'services/update_service.dart';
import 'app/dynamic_island_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // Window kecil = pill. Transparan, always-on-top, tidak ada di taskbar.
  const options = WindowOptions(
    size: Size(150, 36),
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    // Setiap pengaturan opsional dibungkus try/catch: tidak semua method
    // window_manager tersedia di semua platform (mis. setHasShadow di Linux).
    Future<void> safe(Future<void> Function() f) async {
      try {
        await f();
      } catch (_) {}
    }

    await safe(() => windowManager.setAsFrameless());
    await safe(() => windowManager.setBackgroundColor(Colors.transparent));
    await safe(() => windowManager.setAlwaysOnTop(true));
    if (!Platform.isLinux) {
      await safe(() => windowManager.setResizable(false));
    }
    if (Platform.isWindows) {
      await safe(() => windowManager.setHasShadow(false)); // hemat GPU
    }
    await windowManager.show();
  });

  // System tray (opsional, gagal = dilewati)
  if (Platform.isWindows || Platform.isLinux) {
    try {
      await trayManager.setIcon(Platform.isWindows
          ? 'assets/icons/tray_icon.ico'
          : 'assets/icons/tray_icon.png');
      try {
        await trayManager.setToolTip('Dynamic Island');
      } catch (_) {}
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show', label: 'Show Dynamic Island'),
        MenuItem(key: 'dnd', label: 'Toggle DND'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: 'Exit'),
      ]));
    } catch (_) {}
  }

  runApp(const DynamicIslandRoot());
}

class DynamicIslandRoot extends StatelessWidget {
  const DynamicIslandRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()..load()),
        ChangeNotifierProvider(create: (_) => MusicProvider()..start()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => WeatherProvider()..fetchWeather()),
        ChangeNotifierProvider(create: (_) => AlarmProvider()..load()..start()),
        ChangeNotifierProvider(create: (_) => WellnessProvider()..load()..start()),
        ChangeNotifierProvider(create: (_) => DndProvider()),
        ChangeNotifierProvider(create: (_) => LyricsProvider()),
        ChangeNotifierProvider(create: (_) => BatteryProvider()..start()),
        ChangeNotifierProvider(create: (_) => PerformanceProvider()),
        ChangeNotifierProvider(create: (_) => UpdateService()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (_, s, __) => MaterialApp(
          title: 'Dynamic Island',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: Colors.transparent,
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF0A84FF),
              secondary: Color(0xFF30D158),
              surface: Color(0xFF1C1C1E),
            ),
            useMaterial3: true,
          ),
          locale: s.locale,
          supportedLocales: const [Locale('en'), Locale('id')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const DynamicIslandApp(),
        ),
      ),
    );
  }
}