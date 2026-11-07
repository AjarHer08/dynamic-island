import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Alarm {
  final String id;
  int hour, minute;
  String label;
  bool enabled;

  /// Hari berulang (DateTime.monday=1 ... sunday=7). Kosong = sekali saja.
  Set<int> days;
  DateTime? nextFire;

  Alarm({
    required this.id,
    required this.hour,
    required this.minute,
    this.label = '',
    this.enabled = true,
    Set<int>? days,
  }) : days = days ?? <int>{};

  Map<String, dynamic> toJson() => {
        'id': id,
        'h': hour,
        'm': minute,
        'label': label,
        'on': enabled,
        'days': days.toList(),
      };

  factory Alarm.fromJson(Map<String, dynamic> j) => Alarm(
        id: j['id'] as String,
        hour: j['h'] as int,
        minute: j['m'] as int,
        label: (j['label'] as String?) ?? '',
        enabled: (j['on'] as bool?) ?? true,
        days: ((j['days'] as List?) ?? const []).map((e) => e as int).toSet(),
      );
}

class AlarmProvider extends ChangeNotifier {
  final List<Alarm> _alarms = [];
  Timer? _ticker;
  Alarm? _ringing;
  void Function(Alarm)? onAlarmFired;

  List<Alarm> get alarms => List.unmodifiable(_alarms);
  Alarm? get ringing => _ringing;

  /// Waktu bunyi berikutnya (selalu di masa depan) atau null.
  static DateTime? computeNext(Alarm a, DateTime now) {
    for (var off = 0; off <= 7; off++) {
      final c = DateTime(now.year, now.month, now.day + off, a.hour, a.minute);
      if (!c.isAfter(now)) continue;
      if (a.days.isEmpty || a.days.contains(c.weekday)) return c;
    }
    return null;
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('alarms');
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        _alarms
          ..clear()
          ..addAll(list.map((e) => Alarm.fromJson(e as Map<String, dynamic>)));
      } catch (_) {}
    }
    final now = DateTime.now();
    for (final a in _alarms) {
      a.nextFire = a.enabled ? computeNext(a, now) : null;
    }
    _sort();
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('alarms', jsonEncode(_alarms.map((a) => a.toJson()).toList()));
  }

  void _sort() => _alarms.sort((a, b) =>
      (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));

  void add(int hour, int minute, String label, Set<int> days) {
    final a = Alarm(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      hour: hour,
      minute: minute,
      label: label,
      days: days,
    );
    a.nextFire = computeNext(a, DateTime.now());
    _alarms.add(a);
    _sort();
    _save();
    notifyListeners();
  }

  void setEnabled(String id, bool on) {
    for (final a in _alarms) {
      if (a.id == id) {
        a.enabled = on;
        a.nextFire = on ? computeNext(a, DateTime.now()) : null;
      }
    }
    _save();
    notifyListeners();
  }

  void remove(String id) {
    _alarms.removeWhere((a) => a.id == id);
    _save();
    notifyListeners();
  }

  void stopRinging() {
    if (_ringing != null) {
      _ringing = null;
      notifyListeners();
    }
  }

  /// Dicek tiap detik terhadap jam dinding (bukan hitung mundur), jadi tetap
  /// akurat setelah laptop sleep. Alarm yang terlewat > 2 menit tidak dibunyikan.
  void start() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final now = DateTime.now();
    var changed = false;
    for (final a in _alarms) {
      if (!a.enabled) continue;
      a.nextFire ??= computeNext(a, now);
      final nf = a.nextFire;
      if (nf != null && !now.isBefore(nf)) {
        if (now.difference(nf) < const Duration(minutes: 2)) {
          _ringing = a;
          onAlarmFired?.call(a);
        }
        if (a.days.isEmpty) {
          a.enabled = false;
          a.nextFire = null;
        } else {
          a.nextFire = computeNext(a, now);
        }
        changed = true;
      }
    }
    if (changed) {
      _save();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
