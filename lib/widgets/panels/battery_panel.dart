import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/battery_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/island_theme.dart';
import '../liquid_glass.dart';
import '../../utils/tr.dart';

Color batteryColor(int pct, bool charging, IslandTheme t) {
  if (charging) return const Color(0xFF30D158);
  if (pct <= 15) return const Color(0xFFFF453A);
  if (pct <= 30) return const Color(0xFFFF9F0A);
  return t.accentColor;
}

IconData batteryIcon(int pct, bool charging) {
  if (charging) return Icons.battery_charging_full;
  if (pct <= 10) return Icons.battery_alert;
  if (pct <= 25) return Icons.battery_2_bar;
  if (pct <= 50) return Icons.battery_4_bar;
  if (pct <= 75) return Icons.battery_5_bar;
  return Icons.battery_full;
}

IconData _deviceIcon(String icon) {
  if (icon.contains('headset')) return Icons.headset_mic;
  if (icon.contains('headphone')) return Icons.headphones;
  if (icon.contains('speaker')) return Icons.speaker;
  if (icon.contains('mouse')) return Icons.mouse;
  if (icon.contains('keyboard')) return Icons.keyboard;
  if (icon.contains('phone')) return Icons.smartphone;
  if (icon.contains('gaming')) return Icons.sports_esports;
  return Icons.bluetooth;
}

class BatteryPanel extends StatelessWidget {
  const BatteryPanel({super.key});

  String _duration(BuildContext context, Duration d) {
    final h = d.inHours, m = d.inMinutes % 60;
    return h > 0
        ? tr(context, '$h j $m mnt', '${h}h ${m}m')
        : tr(context, '$m mnt', '${m}m');
  }

  String _stateText(BuildContext context, LaptopBattery b) {
    final rem = b.remaining == null ? null : _duration(context, b.remaining!);
    switch (b.state) {
      case PowerState.charging:
        return rem == null
            ? tr(context, 'Mengisi daya', 'Charging')
            : tr(context, 'Mengisi daya · penuh dalam $rem',
                'Charging · full in $rem');
      case PowerState.discharging:
        return rem == null
            ? tr(context, 'Memakai baterai', 'On battery')
            : tr(context, 'Memakai baterai · sisa $rem',
                'On battery · $rem left');
      case PowerState.full:
        return tr(context, 'Penuh', 'Fully charged');
      case PowerState.pluggedIn:
        return tr(context, 'Tersambung ke listrik', 'Plugged in');
      case PowerState.unknown:
        return '';
    }
  }

  Widget _bar(double value, Color color) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0).toDouble(),
          minHeight: 6,
          backgroundColor: Colors.white.withValues(alpha: 0.1),
          valueColor: AlwaysStoppedAnimation(color),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final b = context.watch<BatteryProvider>();
    final t = context.watch<SettingsProvider>().theme;
    final lap = b.laptop;
    final noReport = b.devices.any((d) => d.percent == null);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.battery_full, size: 14, color: t.accentColor),
            const SizedBox(width: 6),
            Text(tr(context, 'BATERAI', 'BATTERY'),
                style: t.subtitleStyle.copyWith(letterSpacing: 1)),
            const Spacer(),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: b.refreshing ? null : b.refresh,
              child: b.refreshing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 16, color: Colors.white54),
            ),
          ]),
          const SizedBox(height: 12),

          // ---- Laptop ----
          Text(tr(context, 'Laptop', 'Laptop'),
              style: t.titleStyle.copyWith(fontSize: 11, color: Colors.white54)),
          const SizedBox(height: 6),
          if (!b.loaded)
            Text(tr(context, 'Membaca...', 'Reading...'), style: t.subtitleStyle)
          else if (lap == null)
            Text(
                tr(context, 'Baterai laptop tidak terdeteksi',
                    'No laptop battery detected'),
                style: t.subtitleStyle)
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: cardDecoration(t, radius: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Icon(
                      batteryIcon(
                          lap.percent, lap.state == PowerState.charging),
                      size: 30,
                      color: batteryColor(
                          lap.percent, lap.state == PowerState.charging, t)),
                  const SizedBox(width: 10),
                  Text('${lap.percent}%',
                      style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w300,
                          color: Colors.white)),
                ]),
                const SizedBox(height: 8),
                _bar(lap.percent / 100,
                    batteryColor(lap.percent, lap.state == PowerState.charging, t)),
                if (_stateText(context, lap).isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(_stateText(context, lap),
                      style: t.subtitleStyle.copyWith(fontSize: 10)),
                ],
              ]),
            ),
          const Divider(height: 24, color: Colors.white10),

          // ---- Bluetooth ----
          Row(children: [
            Icon(Icons.bluetooth_connected, size: 14, color: t.accentColor),
            const SizedBox(width: 6),
            Text(tr(context, 'Bluetooth & perangkat', 'Bluetooth & devices'),
                style: t.titleStyle.copyWith(fontSize: 11, color: Colors.white54)),
          ]),
          const SizedBox(height: 8),
          if (!b.loaded)
            Text(tr(context, 'Membaca...', 'Reading...'), style: t.subtitleStyle)
          else if (b.devices.isEmpty)
            Text(
                b.bluetoothReadable
                    ? tr(context, 'Tidak ada perangkat Bluetooth yang terhubung',
                        'No connected Bluetooth devices')
                    : tr(context, 'Bluetooth tidak bisa dibaca (BlueZ tidak aktif?)',
                        'Bluetooth unavailable (is BlueZ running?)'),
                style: t.subtitleStyle)
          else
            ...b.devices.map((d) {
              final pct = d.percent;
              final color = pct == null ? Colors.white38 : batteryColor(pct, false, t);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    Icon(_deviceIcon(d.icon), size: 20, color: t.accentColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.name,
                              style: t.titleStyle.copyWith(fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 5),
                          if (pct != null)
                            _bar(pct / 100, color)
                          else
                            Text(
                                tr(context, 'Baterai tidak dilaporkan',
                                    'Battery not reported'),
                                style: t.subtitleStyle.copyWith(fontSize: 10)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(pct == null ? '--' : '$pct%',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w300,
                            color: pct == null ? Colors.white38 : Colors.white)),
                  ]),
                ),
              );
            }),
          if (noReport)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                tr(
                    context,
                    'Sebagian headset baru melaporkan baterai bila BlueZ mode experimental aktif: '
                    'isi "Experimental = true" di /etc/bluetooth/main.conf, lalu '
                    'jalankan: sudo systemctl restart bluetooth',
                    'Some headsets only report battery when BlueZ experimental mode is on: '
                    'set "Experimental = true" in /etc/bluetooth/main.conf, then run: '
                    'sudo systemctl restart bluetooth'),
                style: t.subtitleStyle.copyWith(fontSize: 9),
              ),
            ),
        ],
      ),
    );
  }
}
