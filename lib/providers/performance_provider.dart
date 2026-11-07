import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Info GPU. Field yang tidak bisa dibaca bernilai null.
class GpuInfo {
  const GpuInfo({
    this.name = '',
    this.usage,
    this.tempC,
    this.memUsedMb,
    this.memTotalMb,
    this.freqMhz,
  });
  final String name;

  /// Pemakaian 0-100 (%).
  final double? usage;
  final double? tempC;
  final int? memUsedMb, memTotalMb;

  /// Dipakai bila pemakaian % tidak tersedia (mis. GPU Intel).
  final int? freqMhz;
}

/// Membaca pemakaian CPU, RAM, dan GPU.
///
/// Linux  : /proc/stat, /proc/meminfo, hwmon; GPU lewat nvidia-smi (NVIDIA),
///          sysfs amdgpu (AMD), atau sysfs i915 (Intel, hanya frekuensi).
/// Windows: PowerShell (CPU/RAM) dan nvidia-smi bila ada.
///
/// Polling hanya berjalan selama ada panel yang membuka [acquire].
class PerformanceProvider extends ChangeNotifier {
  double cpu = 0;
  double? cpuTemp;
  int ramUsedMb = 0, ramTotalMb = 0;
  GpuInfo? gpu;
  bool loaded = false;
  final List<double> cpuHistory = [];

  int _refs = 0;
  Timer? _timer;
  bool _busy = false;
  bool _disposed = false;
  bool _noNvidia = false;
  List<int>? _prev; // [total, idle] sampel /proc/stat sebelumnya

  double get ramFraction =>
      ramTotalMb <= 0 ? 0 : (ramUsedMb / ramTotalMb).clamp(0.0, 1.0).toDouble();

  void acquire() {
    _refs++;
    if (_refs == 1) {
      _prev = null;
      _tick();
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
    }
  }

  void release() {
    if (_refs > 0) _refs--;
    if (_refs == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _tick() async {
    if (_busy || _disposed) return;
    _busy = true;
    try {
      if (Platform.isLinux) {
        await _linuxCpu();
        await _linuxRam();
        cpuTemp = await _linuxCpuTemp();
        gpu = await _gpu();
      } else if (Platform.isWindows) {
        await _windowsCpuRam();
        gpu = await _nvidia();
      }
      cpuHistory.add(cpu);
      if (cpuHistory.length > 40) cpuHistory.removeAt(0);
      loaded = true;
    } catch (_) {
      // Pembacaan gagal: pertahankan data terakhir.
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  // ---------------------------------------------------------------- util

  static Future<String?> _read(String path) async {
    try {
      return (await File(path).readAsString()).trim();
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _exec(String exe, List<String> args) async {
    try {
      final r = await Process.run(exe, args).timeout(const Duration(seconds: 4));
      return r.exitCode == 0 ? r.stdout.toString() : null;
    } catch (_) {
      return null;
    }
  }

  static Future<List<String>> _ls(String dir, String prefix) async {
    try {
      final d = Directory(dir);
      if (!await d.exists()) return const [];
      final out = (await d.list().toList())
          .map((e) => e.path)
          .where((p) => p.split('/').last.startsWith(prefix))
          .toList()
        ..sort();
      return out;
    } catch (_) {
      return const [];
    }
  }

  // --------------------------------------------------------------- Linux

  Future<List<int>?> _readStat() async {
    final s = await _read('/proc/stat');
    if (s == null) return null;
    final line = s.split('\n').firstWhere((l) => l.startsWith('cpu '),
        orElse: () => '');
    final p = line
        .split(RegExp(r'\s+'))
        .skip(1)
        .map(int.tryParse)
        .whereType<int>()
        .toList();
    if (p.length < 5) return null;
    final total = p.take(8).fold<int>(0, (a, b) => a + b);
    final idle = p[3] + p[4]; // idle + iowait
    return [total, idle];
  }

  Future<void> _linuxCpu() async {
    var prev = _prev;
    if (prev == null) {
      prev = await _readStat();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    final now = await _readStat();
    if (prev == null || now == null) return;
    final dTotal = now[0] - prev[0];
    final dIdle = now[1] - prev[1];
    if (dTotal > 0) {
      cpu = ((dTotal - dIdle) / dTotal * 100).clamp(0.0, 100.0).toDouble();
    }
    _prev = now;
  }

  Future<void> _linuxRam() async {
    final s = await _read('/proc/meminfo');
    if (s == null) return;
    int? kb(String key) {
      final m = RegExp('^$key:\\s+(\\d+)', multiLine: true).firstMatch(s);
      return m == null ? null : int.tryParse(m.group(1)!);
    }

    final total = kb('MemTotal');
    final avail = kb('MemAvailable') ?? kb('MemFree');
    if (total == null || avail == null) return;
    ramTotalMb = total ~/ 1024;
    ramUsedMb = (total - avail) ~/ 1024;
  }

  Future<double?> _linuxCpuTemp() async {
    for (final h in await _ls('/sys/class/hwmon', 'hwmon')) {
      final name = await _read('$h/name') ?? '';
      if (name == 'coretemp' || name == 'k10temp' || name == 'zenpower') {
        final v = int.tryParse(await _read('$h/temp1_input') ?? '');
        if (v != null) return v / 1000;
      }
    }
    for (final z in await _ls('/sys/class/thermal', 'thermal_zone')) {
      final type = await _read('$z/type') ?? '';
      if (type == 'x86_pkg_temp' || type.contains('cpu')) {
        final v = int.tryParse(await _read('$z/temp') ?? '');
        if (v != null) return v / 1000;
      }
    }
    return null;
  }

  // ------------------------------------------------------------------ GPU

  Future<GpuInfo?> _gpu() async {
    return await _nvidia() ?? await _amd() ?? await _intel();
  }

  Future<GpuInfo?> _nvidia() async {
    if (_noNvidia) return null;
    final out = await _exec('nvidia-smi', [
      '--query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total',
      '--format=csv,noheader,nounits',
    ]);
    if (out == null || out.trim().isEmpty) {
      _noNvidia = true; // tidak ada NVIDIA / driver: jangan coba lagi
      return null;
    }
    final f = out.trim().split('\n').first.split(',').map((e) => e.trim()).toList();
    if (f.length < 5) return null;
    return GpuInfo(
      name: f[0],
      usage: double.tryParse(f[1]),
      tempC: double.tryParse(f[2]),
      memUsedMb: int.tryParse(f[3]),
      memTotalMb: int.tryParse(f[4]),
    );
  }

  Future<GpuInfo?> _amd() async {
    for (final c in await _ls('/sys/class/drm', 'card')) {
      if (c.contains('-')) continue; // lewati cardN-HDMI-A-1 dll.
      final dev = '$c/device';
      final busy = double.tryParse(await _read('$dev/gpu_busy_percent') ?? '');
      if (busy == null) continue;
      final used = int.tryParse(await _read('$dev/mem_info_vram_used') ?? '');
      final total = int.tryParse(await _read('$dev/mem_info_vram_total') ?? '');
      double? temp;
      for (final h in await _ls('$dev/hwmon', 'hwmon')) {
        final v = int.tryParse(await _read('$h/temp1_input') ?? '');
        if (v != null) {
          temp = v / 1000;
          break;
        }
      }
      return GpuInfo(
        name: 'AMD GPU',
        usage: busy,
        tempC: temp,
        memUsedMb: used == null ? null : used ~/ (1024 * 1024),
        memTotalMb: total == null ? null : total ~/ (1024 * 1024),
      );
    }
    return null;
  }

  /// GPU Intel tidak menyediakan persentase lewat sysfs; tampilkan frekuensi.
  Future<GpuInfo?> _intel() async {
    for (final c in await _ls('/sys/class/drm', 'card')) {
      if (c.contains('-')) continue;
      if ((await _read('$c/device/vendor')) != '0x8086') continue;
      final cur = int.tryParse(await _read('$c/gt_cur_freq_mhz') ?? '');
      if (cur == null) continue;
      return GpuInfo(name: 'Intel GPU', freqMhz: cur);
    }
    return null;
  }

  // -------------------------------------------------------------- Windows

  Future<void> _windowsCpuRam() async {
    final out = await _exec('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r'$c=(Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average;'
          r'$o=Get-CimInstance Win32_OperatingSystem;'
          r'ConvertTo-Json -Compress -InputObject @{cpu=$c;total=$o.TotalVisibleMemorySize;free=$o.FreePhysicalMemory}',
    ]);
    if (out == null) return;
    final j = jsonDecode(out.trim());
    if (j is! Map) return;
    if (j['cpu'] is num) cpu = (j['cpu'] as num).toDouble().clamp(0.0, 100.0).toDouble();
    if (j['total'] is num && j['free'] is num) {
      final t = (j['total'] as num).toInt();
      final f = (j['free'] as num).toInt();
      ramTotalMb = t ~/ 1024;
      ramUsedMb = (t - f) ~/ 1024;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
