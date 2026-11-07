import 'dart:async';
import 'package:flutter/material.dart';

const _daysId = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
const _daysEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _monId = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
const _monEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String twoDigits(int n) => n.toString().padLeft(2, '0');

String longDate(DateTime d, String lang) {
  final id = lang == 'id';
  final day = (id ? _daysId : _daysEn)[d.weekday - 1];
  final mon = (id ? _monId : _monEn)[d.month - 1];
  return '$day, ${d.day} $mon ${d.year}';
}

/// Jam yang di-update tepat di pergantian menit (atau detik), bukan bergantung
/// pada rebuild widget lain.
class LiveClock extends StatefulWidget {
  const LiveClock({super.key, this.seconds = false, this.style});
  final bool seconds;
  final TextStyle? style;

  @override
  State<LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<LiveClock> {
  late DateTime _now;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _schedule();
  }

  void _schedule() {
    _t?.cancel();
    final n = DateTime.now();
    final ms = widget.seconds
        ? 1000 - n.millisecond
        : (60 - n.second) * 1000 - n.millisecond;
    _t = Timer(Duration(milliseconds: ms + 30), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _schedule();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = '${twoDigits(_now.hour)}:${twoDigits(_now.minute)}'
        '${widget.seconds ? ':${twoDigits(_now.second)}' : ''}';
    return Text(s, style: widget.style);
  }
}
