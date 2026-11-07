import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/alarm_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/tr.dart';
import '../live_clock.dart';

const _monthsId = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
  'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
];
const _monthsEn = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _wdId = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
const _wdEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class CalendarPanel extends StatefulWidget {
  const CalendarPanel({super.key});

  @override
  State<CalendarPanel> createState() => _CalendarPanelState();
}

class _CalendarPanelState extends State<CalendarPanel> {
  late DateTime _month; // tanggal 1 dari bulan yang ditampilkan
  late DateTime _selected;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _selected = _day(n);
    _month = DateTime(n.year, n.month);
  }

  void _shift(int months) =>
      setState(() => _month = DateTime(_month.year, _month.month + months));

  void _today() {
    final n = DateTime.now();
    setState(() {
      _selected = _day(n);
      _month = DateTime(n.year, n.month);
    });
  }

  bool _alarmOn(Alarm a, DateTime d) {
    if (!a.enabled) return false;
    if (a.days.isEmpty) {
      final nf = a.nextFire;
      return nf != null && _day(nf) == d;
    }
    return a.days.contains(d.weekday);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsProvider>().theme;
    final alarms = context.watch<AlarmProvider>().alarms;
    final lang = Localizations.localeOf(context).languageCode;
    final id = lang == 'id';
    final today = _day(DateTime.now());

    final leading = _month.weekday - 1; // kolom awal (Senin = 0)
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final rows = ((leading + daysInMonth) / 7).ceil();

    Widget navBtn(IconData icon, VoidCallback onTap) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Icon(icon, size: 20, color: Colors.white70),
          ),
        );

    Widget cell(int dayNum) {
      final d = DateTime(_month.year, _month.month, dayNum);
      final isToday = d == today;
      final isSel = d == _selected;
      final hasAlarm = alarms.any((a) => _alarmOn(a, d));
      final isSunday = d.weekday == DateTime.sunday;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _selected = d),
          child: Container(
            height: 30,
            margin: const EdgeInsets.all(1.5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isToday ? t.accentColor : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isSel && !isToday
                  ? Border.all(color: t.accentColor, width: 1.2)
                  : null,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$dayNum',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                    color: isToday
                        ? Colors.black
                        : (isSunday ? const Color(0xFFFF6B6B) : Colors.white),
                  )),
              if (hasAlarm)
                Container(
                  width: 4,
                  height: 4,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    color: isToday ? Colors.black : t.accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
            ]),
          ),
        ),
      );
    }

    final dayAlarms = alarms.where((a) => _alarmOn(a, _selected)).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.calendar_month, size: 14, color: t.accentColor),
            const SizedBox(width: 6),
            Text(tr(context, 'KALENDER', 'CALENDAR'),
                style: t.subtitleStyle.copyWith(letterSpacing: 1)),
            const Spacer(),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _today,
              child: Text(tr(context, 'Hari ini', 'Today'),
                  style: t.subtitleStyle.copyWith(color: t.accentColor)),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            navBtn(Icons.chevron_left, () => _shift(-1)),
            Expanded(
              child: Text(
                '${(id ? _monthsId : _monthsEn)[_month.month - 1]} ${_month.year}',
                textAlign: TextAlign.center,
                style: t.titleStyle.copyWith(fontSize: 14),
              ),
            ),
            navBtn(Icons.chevron_right, () => _shift(1)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text((id ? _wdId : _wdEn)[i],
                      style: t.subtitleStyle.copyWith(
                          fontSize: 10,
                          color: i == 6
                              ? const Color(0xFFFF6B6B)
                              : t.subtitleStyle.color)),
                ),
              ),
          ]),
          const SizedBox(height: 4),
          for (var r = 0; r < rows; r++)
            Row(children: [
              for (var c = 0; c < 7; c++)
                () {
                  final n = r * 7 + c - leading + 1;
                  if (n < 1 || n > daysInMonth) {
                    return const Expanded(child: SizedBox(height: 30));
                  }
                  return cell(n);
                }(),
            ]),
          const Divider(height: 20, color: Colors.white10),
          Text(longDate(_selected, lang),
              style: t.titleStyle.copyWith(fontSize: 12)),
          const SizedBox(height: 4),
          if (dayAlarms.isEmpty)
            Text(tr(context, 'Tidak ada alarm di hari ini', 'No alarms on this day'),
                style: t.subtitleStyle.copyWith(fontSize: 10))
          else
            for (final a in dayAlarms)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(children: [
                  Icon(Icons.alarm, size: 12, color: t.accentColor),
                  const SizedBox(width: 6),
                  Text('${twoDigits(a.hour)}:${twoDigits(a.minute)}',
                      style: t.titleStyle.copyWith(fontSize: 12)),
                  if (a.label.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(a.label,
                          style: t.subtitleStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ]),
              ),
        ],
      ),
    );
  }
}
