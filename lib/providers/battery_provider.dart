import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

enum PowerState { unknown, charging, discharging, full, pluggedIn }

/// Baterai laptop.
class LaptopBattery {
  const LaptopBattery(this.percent, this.state, this.remaining);
  final int percent;
  final PowerState state;

  /// Perkiraan sisa waktu (discharging) atau waktu sampai penuh (charging).
  final Duration? remaining;
}

/// Baterai perangkat yang terhubung (headset/mouse/keyboard Bluetooth, dll).
/// [percent] null = perangkat terhubung tetapi tidak melaporkan baterainya.
class DeviceBattery {
  const DeviceBattery(this.name, this.percent, this.icon);
  final String name;
  final int? percent;

  /// Nama ikon dari BlueZ (audio-headset, input-mouse, ...), bisa kosong.
  final String icon;
}

/// Membaca baterai laptop dan perangkat Bluetooth.
///
/// Linux : laptop dari /sys/class/power_supply; Bluetooth dari BlueZ lewat
///         D-Bus (org.bluez.Battery1), ditambah perangkat sysfs (scope=Device).
/// Windows: PowerShell (Win32_Battery; properti baterai Bluetooth dari PnP).
class BatteryProvider extends ChangeNotifier {
  LaptopBattery? _laptop;
  List<DeviceBattery> _devices = const [];
  bool _btReadable = false;
  bool _loaded = false;
  bool _busy = false;
  bool _disposed = false;
  DateTime? _updated;
  Timer? _timer;
  DBusClient? _sys;

  LaptopBattery? get laptop => _laptop;
  List<DeviceBattery> get devices => _devices;

  /// false bila Bluetooth/BlueZ tidak bisa dibaca sama sekali.
  bool get bluetoothReadable => _btReadable;
  bool get loaded => _loaded;
  bool get refreshing => _busy;
  DateTime? get updated => _updated;

  void start() {
    refresh();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    if (_loaded) _safeNotify();
    try {
      if (Platform.isLinux) {
        _laptop = await _linuxLaptop();
        final bt = await _linuxBluetooth();
        final extra = await _linuxPeripherals();
        _btReadable = bt != null;
        _devices = _merge(bt ?? const [], extra);
      } else if (Platform.isWindows) {
        _laptop = await _windowsLaptop();
        final bt = await _windowsBluetooth();
        _btReadable = bt != null;
        _devices = bt ?? const [];
      }
      _updated = DateTime.now();
    } catch (_) {
      // Pembacaan gagal: pertahankan data terakhir.
    } finally {
      _busy = false;
      _loaded = true;
      _safeNotify();
    }
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  static List<DeviceBattery> _merge(
      List<DeviceBattery> bt, List<DeviceBattery> extra) {
    final out = [...bt];
    for (final e in extra) {
      final n = e.name.toLowerCase();
      final dup = out.any((b) {
        final bn = b.name.toLowerCase();
        return bn.contains(n) || n.contains(bn);
      });
      if (!dup) out.add(e);
    }
    return out;
  }

  // ------------------------------------------------------------ Linux

  static Future<String?> _read(String path) async {
    try {
      return (await File(path).readAsString()).trim();
    } catch (_) {
      return null;
    }
  }

  static Future<List<String>> _powerSupplies() async {
    try {
      final dir = Directory('/sys/class/power_supply');
      if (!await dir.exists()) return const [];
      final paths = (await dir.list().toList()).map((e) => e.path).toList()
        ..sort();
      return paths;
    } catch (_) {
      return const [];
    }
  }

  static Future<LaptopBattery?> _linuxLaptop() async {
    for (final dir in await _powerSupplies()) {
      if (await _read('$dir/type') != 'Battery') continue;
      if (await _read('$dir/scope') == 'Device') continue; // bukan laptop
      final cap = int.tryParse(await _read('$dir/capacity') ?? '');
      if (cap == null) continue;

      final status = (await _read('$dir/status') ?? '').toLowerCase();
      final state = switch (status) {
        'charging' => PowerState.charging,
        'discharging' => PowerState.discharging,
        'full' => PowerState.full,
        'not charging' => PowerState.pluggedIn,
        _ => PowerState.unknown,
      };

      Future<double?> readNum(String f) async =>
          double.tryParse(await _read('$dir/$f') ?? '');
      final now = await readNum('energy_now') ?? await readNum('charge_now');
      final full = await readNum('energy_full') ?? await readNum('charge_full');
      final rate = await readNum('power_now') ?? await readNum('current_now');

      Duration? remaining;
      if (rate != null && rate > 0 && now != null) {
        double? hours;
        if (state == PowerState.discharging) {
          hours = now / rate;
        } else if (state == PowerState.charging && full != null) {
          hours = (full - now) / rate;
        }
        if (hours != null && hours > 0 && hours < 48) {
          remaining = Duration(minutes: (hours * 60).round());
        }
      }
      return LaptopBattery(cap.clamp(0, 100).toInt(), state, remaining);
    }
    return null;
  }

  /// Perangkat periferal yang dilaporkan kernel (mouse/keyboard HID, dll).
  static Future<List<DeviceBattery>> _linuxPeripherals() async {
    final out = <DeviceBattery>[];
    for (final dir in await _powerSupplies()) {
      if (await _read('$dir/type') != 'Battery') continue;
      if (await _read('$dir/scope') != 'Device') continue;
      final cap = int.tryParse(await _read('$dir/capacity') ?? '');
      if (cap == null) continue;
      var name = await _read('$dir/model_name') ?? '';
      if (name.isEmpty) name = dir.split('/').last;
      out.add(DeviceBattery(name, cap.clamp(0, 100).toInt(), ''));
    }
    return out;
  }

  /// Perangkat Bluetooth yang sedang terhubung, via BlueZ.
  /// Mengembalikan null bila BlueZ tidak bisa dihubungi.
  Future<List<DeviceBattery>?> _linuxBluetooth() async {
    try {
      final c = _sys ??= DBusClient.system();
      final obj = DBusRemoteObject(c,
          name: 'org.bluez', path: DBusObjectPath('/'));
      final res = await obj.callMethod(
        'org.freedesktop.DBus.ObjectManager',
        'GetManagedObjects',
        [],
        replySignature: DBusSignature('a{oa{sa{sv}}}'),
      );
      final native = res.returnValues.first.toNative();
      final out = <DeviceBattery>[];
      if (native is Map) {
        for (final ifaces in native.values) {
          if (ifaces is! Map) continue;
          final dev = ifaces['org.bluez.Device1'];
          if (dev is! Map || dev['Connected'] != true) continue;
          int? pct;
          final bat = ifaces['org.bluez.Battery1'];
          if (bat is Map && bat['Percentage'] is num) {
            pct = (bat['Percentage'] as num).toInt().clamp(0, 100).toInt();
          }
          final name =
              (dev['Alias'] ?? dev['Name'] ?? dev['Address'] ?? '').toString();
          if (name.isEmpty) continue;
          out.add(DeviceBattery(name, pct, (dev['Icon'] ?? '').toString()));
        }
      }
      out.sort((a, b) => a.name.compareTo(b.name));
      return out;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------- Windows

  static Future<dynamic> _powershell(String script) async {
    try {
      final p = await Process.start(
          'powershell', ['-NoProfile', '-NonInteractive', '-Command', script]);
      p.stderr.drain<void>();
      final outF = p.stdout.transform(utf8.decoder).join();
      final code = await p.exitCode.timeout(const Duration(seconds: 10),
          onTimeout: () {
        p.kill();
        return -1;
      });
      if (code != 0) return null;
      final text = (await outF).trim();
      return text.isEmpty ? null : jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  static Future<LaptopBattery?> _windowsLaptop() async {
    final j = await _powershell(
        'Get-CimInstance Win32_Battery | Select-Object -First 1 '
        'EstimatedChargeRemaining,BatteryStatus,EstimatedRunTime | '
        'ConvertTo-Json -Compress');
    if (j is! Map || j['EstimatedChargeRemaining'] is! num) return null;
    final pct = (j['EstimatedChargeRemaining'] as num).toInt().clamp(0, 100).toInt();
    final st = (j['BatteryStatus'] as num?)?.toInt() ?? 0;
    final state = switch (st) {
      1 || 4 || 5 => PowerState.discharging,
      2 => PowerState.pluggedIn,
      3 => PowerState.full,
      6 || 7 || 8 || 9 => PowerState.charging,
      _ => PowerState.unknown,
    };
    Duration? remaining;
    final run = j['EstimatedRunTime'];
    if (state == PowerState.discharging &&
        run is num &&
        run > 0 &&
        run < 60 * 48) {
      remaining = Duration(minutes: run.toInt());
    }
    return LaptopBattery(pct, state, remaining);
  }

  static Future<List<DeviceBattery>?> _windowsBluetooth() async {
    final j = await _powershell(r'''
$r = @()
Get-PnpDevice -Class Bluetooth -PresentOnly -ErrorAction SilentlyContinue | ForEach-Object {
  $p = Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName '{104EA319-6EE2-4701-BD47-8DDF5BBD6D5E} 2' -ErrorAction SilentlyContinue
  if ($p -and $p.Data -ne $null) { $r += [pscustomobject]@{ name = $_.FriendlyName; pct = [int]$p.Data } }
}
ConvertTo-Json -InputObject @($r) -Compress
''');
    if (j == null) return null;
    final list = j is List ? j : [j];
    return [
      for (final e in list)
        if (e is Map && e['pct'] is num)
          DeviceBattery((e['name'] ?? '').toString(),
              (e['pct'] as num).toInt().clamp(0, 100).toInt(), ''),
    ];
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _sys?.close();
    super.dispose();
  }
}
