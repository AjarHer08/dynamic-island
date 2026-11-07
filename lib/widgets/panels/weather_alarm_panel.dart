import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/alarm_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/weather_provider.dart';
import '../../theme/island_theme.dart';
import '../live_clock.dart';

const _dayShortId = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
const _dayShortEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

enum _Mode { main, city, alarm }

/// Catatan: pemilih kota & editor alarm dibuat INLINE (bukan showDialog).
/// Dialog membuat route baru di Navigator; saat island menutup sendiri
/// (klik di luar) atau route di-pop dua kali, Navigator kehabisan route dan
/// melempar `_history.isNotEmpty is not true`.
class WeatherAlarmPanel extends StatefulWidget {
  const WeatherAlarmPanel({super.key});

  @override
  State<WeatherAlarmPanel> createState() => _WeatherAlarmPanelState();
}

class _WeatherAlarmPanelState extends State<WeatherAlarmPanel> {
  _Mode _mode = _Mode.main;

  void _setMode(_Mode m) {
    if (mounted) setState(() => _mode = m);
  }

  String _repeatText(Alarm a, String lang, AppLocalizations l10n) {
    if (a.days.isEmpty) return l10n.once;
    if (a.days.length == 7) return l10n.everyDay;
    final names = lang == 'id' ? _dayShortId : _dayShortEn;
    final sorted = a.days.toList()..sort();
    return sorted.map((d) => names[d - 1]).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final weather = context.watch<WeatherProvider>();
    final alarms = context.watch<AlarmProvider>();
    final settings = context.watch<SettingsProvider>();
    final l10n = AppLocalizations.of(context)!;
    final t = settings.theme;
    final lang = Localizations.localeOf(context).languageCode;

    if (_mode == _Mode.city) {
      return _CityPicker(
          weather: weather, t: t, lang: lang, onClose: () => _setMode(_Mode.main));
    }
    if (_mode == _Mode.alarm) {
      return _AlarmEditor(
        t: t,
        lang: lang,
        onCancel: () => _setMode(_Mode.main),
        onSave: (d) {
          alarms.add(d.hour, d.minute, d.label, d.days);
          _setMode(_Mode.main);
        },
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.schedule, size: 14, color: t.accentColor),
            const SizedBox(width: 6),
            Text(l10n.clock, style: t.subtitleStyle.copyWith(letterSpacing: 1)),
          ]),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const LiveClock(
              seconds: true,
              style: TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w300, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: _DateText(lang: lang, style: t.subtitleStyle),
            ),
          ]),
          const Divider(height: 18, color: Colors.white10),
          Row(children: [
            Icon(Icons.location_on, size: 14, color: t.accentColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(weather.city,
                  style: t.subtitleStyle.copyWith(letterSpacing: 1),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            GestureDetector(
              onTap: () => _setMode(_Mode.city),
              child: Icon(Icons.edit_location_alt,
                  size: 18, color: t.accentColor),
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Icon(weatherIcon(weather.code, weather.isDay),
                size: 34, color: t.accentColor),
            const SizedBox(width: 10),
            Text(
              weather.tempC != null
                  ? '${weather.tempC!.toStringAsFixed(0)}°'
                  : '--°',
              style: const TextStyle(
                  fontSize: 34, fontWeight: FontWeight.w300, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(weatherLabel(weather.code, lang), style: t.titleStyle),
                  if (weather.highC != null && weather.lowC != null)
                    Text(
                        '${l10n.high} ${weather.highC!.toStringAsFixed(0)}°  '
                        '${l10n.low} ${weather.lowC!.toStringAsFixed(0)}°',
                        style: t.subtitleStyle),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 12, runSpacing: 2, children: [
            if (weather.feelsC != null)
              Text('${l10n.feelsLike} ${weather.feelsC!.toStringAsFixed(0)}°',
                  style: t.subtitleStyle.copyWith(fontSize: 10)),
            if (weather.humidity != null)
              Text('${l10n.humidity} ${weather.humidity}%',
                  style: t.subtitleStyle.copyWith(fontSize: 10)),
            if (weather.windKmh != null)
              Text('${l10n.wind} ${weather.windKmh!.toStringAsFixed(0)} km/h',
                  style: t.subtitleStyle.copyWith(fontSize: 10)),
            if (weather.rainChance != null)
              Text('${l10n.rainChance} ${weather.rainChance}%',
                  style: t.subtitleStyle.copyWith(fontSize: 10)),
            if (weather.error != null)
              Text(weather.error!,
                  style: t.subtitleStyle
                      .copyWith(fontSize: 10, color: Colors.orangeAccent)),
          ]),
          const Divider(height: 18, color: Colors.white10),
          Row(children: [
            Icon(Icons.alarm, size: 14, color: t.accentColor),
            const SizedBox(width: 6),
            Text(l10n.alarms, style: t.subtitleStyle.copyWith(letterSpacing: 1)),
            const Spacer(),
            GestureDetector(
              onTap: () => _setMode(_Mode.alarm),
              child: Icon(Icons.add_circle_outline,
                  size: 18, color: t.accentColor),
            ),
          ]),
          const SizedBox(height: 6),
          if (alarms.alarms.isEmpty)
            Text(l10n.noAlarms, style: t.subtitleStyle)
          else
            ...alarms.alarms.map((a) {
              final ringing = alarms.ringing?.id == a.id;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Text(
                    '${twoDigits(a.hour)}:${twoDigits(a.minute)}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w300,
                      color: !a.enabled
                          ? Colors.white30
                          : (ringing ? const Color(0xFFFF9F0A) : Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (a.label.isNotEmpty)
                          Text(a.label,
                              style: t.titleStyle.copyWith(fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        Text(_repeatText(a, lang, l10n),
                            style: t.subtitleStyle.copyWith(fontSize: 10)),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => alarms.setEnabled(a.id, !a.enabled),
                    child: Icon(a.enabled ? Icons.toggle_on : Icons.toggle_off,
                        size: 30,
                        color: a.enabled ? t.accentColor : Colors.white30),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => alarms.remove(a.id),
                    child: const Icon(Icons.close,
                        size: 14, color: Colors.white38),
                  ),
                ]),
              );
            }),
        ],
      ),
    );
  }
}

class _DateText extends StatelessWidget {
  const _DateText({required this.lang, required this.style});
  final String lang;
  final TextStyle style;

  @override
  Widget build(BuildContext context) =>
      Text(longDate(DateTime.now(), lang), style: style);
}

class _AlarmDraft {
  final int hour, minute;
  final String label;
  final Set<int> days;
  _AlarmDraft(this.hour, this.minute, this.label, this.days);
}

class _AlarmEditor extends StatefulWidget {
  const _AlarmEditor(
      {required this.t,
      required this.lang,
      required this.onCancel,
      required this.onSave});
  final IslandTheme t;
  final String lang;
  final VoidCallback onCancel;
  final void Function(_AlarmDraft) onSave;

  @override
  State<_AlarmEditor> createState() => _AlarmEditorState();
}

class _AlarmEditorState extends State<_AlarmEditor> {
  late int _h, _m;
  final Set<int> _days = {};
  final _label = TextEditingController();

  @override
  void initState() {
    super.initState();
    final n = DateTime.now().add(const Duration(minutes: 1));
    _h = n.hour;
    _m = n.minute;
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Widget _stepper(int value, int max, int step, void Function(int) onChanged) {
    Widget btn(IconData i, int delta) => GestureDetector(
          onTap: () => onChanged((value + delta + max) % max),
          child: Icon(i, size: 26, color: widget.t.accentColor),
        );
    return Column(children: [
      btn(Icons.keyboard_arrow_up, step),
      Text(twoDigits(value),
          style: const TextStyle(
              fontSize: 34, fontWeight: FontWeight.w300, color: Colors.white)),
      btn(Icons.keyboard_arrow_down, -step),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final l10n = AppLocalizations.of(context)!;
    final names = widget.lang == 'id' ? _dayShortId : _dayShortEn;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(l10n.addAlarm,
                  style: t.subtitleStyle.copyWith(letterSpacing: 1)),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _stepper(_h, 24, 1, (v) => setState(() => _h = v)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text(':',
                      style: TextStyle(fontSize: 34, color: Colors.white54)),
                ),
                _stepper(_m, 60, 1, (v) => setState(() => _m = v)),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 4, runSpacing: 4, children: [
                for (var d = 1; d <= 7; d++)
                  GestureDetector(
                    onTap: () => setState(() =>
                        _days.contains(d) ? _days.remove(d) : _days.add(d)),
                    child: Container(
                      width: 38,
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _days.contains(d)
                            ? t.accentColor
                            : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(names[d - 1],
                          style: TextStyle(
                              fontSize: 10,
                              color: _days.contains(d)
                                  ? Colors.black
                                  : Colors.white70)),
                    ),
                  ),
              ]),
              const SizedBox(height: 4),
              Text(_days.isEmpty ? l10n.once : '',
                  style: t.subtitleStyle.copyWith(fontSize: 10)),
              const SizedBox(height: 4),
              TextField(
                controller: _label,
                style: t.titleStyle.copyWith(fontSize: 12),
                decoration: InputDecoration(
                  hintText: l10n.alarmLabel,
                  hintStyle: t.subtitleStyle,
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                ),
              ),
            ]),
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: widget.onCancel, child: Text(l10n.cancel)),
          TextButton(
            onPressed: () => widget.onSave(
                _AlarmDraft(_h, _m, _label.text.trim(), {..._days})),
            child: Text(l10n.save,
                style: TextStyle(
                    color: t.accentColor, fontWeight: FontWeight.w600)),
          ),
        ]),
      ]),
    );
  }
}


class _CityPicker extends StatefulWidget {
  const _CityPicker(
      {required this.weather,
      required this.t,
      required this.lang,
      required this.onClose});
  final WeatherProvider weather;
  final IslandTheme t;
  final String lang;
  final VoidCallback onClose;

  @override
  State<_CityPicker> createState() => _CityPickerState();
}

class _CityPickerState extends State<_CityPicker> {
  final _q = TextEditingController();
  List<GeoPlace> _results = [];
  bool _busy = false; // sedang mencari
  bool _applying = false; // sedang menerapkan pilihan (cegah ketuk ganda)
  String? _err;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_applying) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final r = await widget.weather.searchCity(_q.text, widget.lang);
      if (!mounted) return;
      setState(() {
        _results = r;
        if (r.isEmpty) _err = '—';
      });
    } catch (_) {
      if (mounted) setState(() => _err = 'Offline');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply(Future<void> Function() action) async {
    if (_applying) return; // ketukan kedua diabaikan
    setState(() => _applying = true);
    try {
      await action();
    } catch (_) {
      // Kegagalan jaringan ditangani WeatherProvider (state error).
    }
    if (mounted) widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.edit_location_alt, size: 14, color: t.accentColor),
          const SizedBox(width: 6),
          Text(l10n.chooseCity,
              style: t.subtitleStyle.copyWith(letterSpacing: 1)),
          const Spacer(),
          GestureDetector(
            onTap: _applying ? null : widget.onClose,
            child: const Icon(Icons.close, size: 16, color: Colors.white54),
          ),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _q,
          autofocus: true,
          enabled: !_applying,
          style: t.titleStyle.copyWith(fontSize: 12),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            hintText: l10n.searchCity,
            hintStyle: t.subtitleStyle,
            isDense: true,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            suffixIcon: GestureDetector(
              onTap: _search,
              child: Icon(Icons.search, size: 18, color: t.accentColor),
            ),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _apply(widget.weather.detectLocation),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Icon(Icons.my_location, size: 14, color: t.accentColor),
              const SizedBox(width: 6),
              Text(l10n.autoLocation,
                  style:
                      t.titleStyle.copyWith(fontSize: 12, color: t.accentColor)),
            ]),
          ),
        ),
        const Divider(height: 10, color: Colors.white10),
        Expanded(
          child: (_busy || _applying)
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : (_err != null
                  ? Center(child: Text(_err!, style: t.subtitleStyle))
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (_, i) {
                        final g = _results[i];
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _apply(() => widget.weather.selectPlace(g)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            child: Text(g.display,
                                style: t.titleStyle.copyWith(fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                        );
                      },
                    )),
        ),
      ]),
    );
  }
}
