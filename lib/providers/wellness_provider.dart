import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WellnessItem {
  final String key; // 'rest' | 'water'
  bool enabled;
  int minutes;
  DateTime? nextDue;
  WellnessItem(this.key, {required this.enabled, required this.minutes});
}

/// Pengingat berkala: istirahat dan minum. Dijadwalkan terhadap jam dinding,
/// jadi tidak meleset setelah sleep. Saat DND aktif, pengingat dilewati diam-diam.
class WellnessProvider extends ChangeNotifier {
  final WellnessItem rest = WellnessItem('rest', enabled: true, minutes: 45);
  final WellnessItem water = WellnessItem('water', enabled: true, minutes: 60);

  bool Function()? isDnd;
  void Function(WellnessItem)? onDue;
  Timer? _ticker;

  List<WellnessItem> get items => [rest, water];

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    for (final i in items) {
      i.enabled = p.getBool('wl_${i.key}_on') ?? i.enabled;
      i.minutes = (p.getInt('wl_${i.key}_min') ?? i.minutes).clamp(5, 240).toInt();
    }
    _reschedule();
    notifyListeners();
  }

  void _reschedule() {
    final now = DateTime.now();
    for (final i in items) {
      i.nextDue = i.enabled ? now.add(Duration(minutes: i.minutes)) : null;
    }
  }

  Future<void> _save(WellnessItem i) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('wl_${i.key}_on', i.enabled);
    await p.setInt('wl_${i.key}_min', i.minutes);
  }

  void setEnabled(WellnessItem i, bool on) {
    i.enabled = on;
    i.nextDue = on ? DateTime.now().add(Duration(minutes: i.minutes)) : null;
    _save(i);
    notifyListeners();
  }

  void setMinutes(WellnessItem i, int minutes) {
    i.minutes = minutes.clamp(5, 240).toInt();
    if (i.enabled) {
      i.nextDue = DateTime.now().add(Duration(minutes: i.minutes));
    }
    _save(i);
    notifyListeners();
  }

  void start() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final now = DateTime.now();
    var changed = false;
    for (final i in items) {
      if (!i.enabled) continue;
      final due = i.nextDue;
      if (due == null) {
        i.nextDue = now.add(Duration(minutes: i.minutes));
        continue;
      }
      if (!now.isBefore(due)) {
        if (!(isDnd?.call() ?? false)) onDue?.call(i);
        i.nextDue = now.add(Duration(minutes: i.minutes));
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
