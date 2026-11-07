import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/dnd_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/wellness_provider.dart';
import '../live_clock.dart';
import '../../theme/island_theme.dart';

class ReminderDndPanel extends StatefulWidget {
  const ReminderDndPanel({super.key});

  @override
  State<ReminderDndPanel> createState() => _ReminderDndPanelState();
}

class _ReminderDndPanelState extends State<ReminderDndPanel> {
  final List<_Reminder> _list = [];
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _wellnessRow(WellnessProvider well, WellnessItem item, IconData icon,
      Color color, String title, AppLocalizations l10n, IslandTheme t) {
    final due = item.nextDue;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Icon(icon, size: 16, color: item.enabled ? color : Colors.white30),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t.titleStyle.copyWith(fontSize: 12)),
              Text(
                item.enabled && due != null
                    ? '${l10n.nextAt} ${twoDigits(due.hour)}:${twoDigits(due.minute)}'
                    : '—',
                style: t.subtitleStyle.copyWith(fontSize: 10),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => well.setMinutes(item, item.minutes - 5),
          child: const Icon(Icons.remove_circle_outline,
              size: 16, color: Colors.white54),
        ),
        SizedBox(
          width: 52,
          child: Text('${item.minutes} min',
              textAlign: TextAlign.center,
              style: t.titleStyle.copyWith(fontSize: 11)),
        ),
        GestureDetector(
          onTap: () => well.setMinutes(item, item.minutes + 5),
          child: const Icon(Icons.add_circle_outline,
              size: 16, color: Colors.white54),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () => well.setEnabled(item, !item.enabled),
          child: Icon(item.enabled ? Icons.toggle_on : Icons.toggle_off,
              size: 30, color: item.enabled ? t.accentColor : Colors.white30),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dnd = context.watch<DndProvider>();
    final settings = context.watch<SettingsProvider>();
    final well = context.watch<WellnessProvider>();
    final l10n = AppLocalizations.of(context)!;
    final t = settings.theme;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.do_not_disturb_on,
                size: 14,
                color: dnd.enabled ? Colors.redAccent : t.accentColor),
            const SizedBox(width: 6),
            Text(l10n.dnd, style: t.subtitleStyle.copyWith(letterSpacing: 1)),
            const Spacer(),
            Switch(
              value: dnd.enabled,
              onChanged: (_) => dnd.toggle(),
              activeThumbColor: t.accentColor,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ]),
          if (dnd.enabled)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(l10n.dndSilenced,
                  style: t.subtitleStyle.copyWith(
                      color: Colors.redAccent, fontSize: 10)),
            ),
          const Divider(height: 16, color: Colors.white10),
          Row(children: [
            Icon(Icons.favorite, size: 14, color: t.accentColor),
            const SizedBox(width: 6),
            Text(l10n.healthReminders,
                style: t.subtitleStyle.copyWith(letterSpacing: 1)),
          ]),
          const SizedBox(height: 6),
          _wellnessRow(well, well.rest, Icons.self_improvement,
              const Color(0xFFBF5AF2), l10n.restReminder, l10n, t),
          _wellnessRow(well, well.water, Icons.water_drop,
              const Color(0xFF64D2FF), l10n.waterReminder, l10n, t),
          const Divider(height: 16, color: Colors.white10),
          Row(children: [
            Icon(Icons.event_note, size: 14, color: t.accentColor),
            const SizedBox(width: 6),
            Text(l10n.reminders,
                style: t.subtitleStyle.copyWith(letterSpacing: 1)),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            style: t.titleStyle.copyWith(fontSize: 12),
            decoration: InputDecoration(
              hintText: l10n.addReminderHint,
              hintStyle: t.subtitleStyle,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (v) {
              if (v.trim().isEmpty) return;
              setState(() {
                _list.insert(0, _Reminder(v.trim(), false));
                _controller.clear();
              });
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _list.isEmpty
                ? Center(child: Text(l10n.noReminders, style: t.subtitleStyle))
                : ListView.builder(
                    itemCount: _list.length,
                    itemBuilder: (_, i) {
                      final r = _list[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(children: [
                          GestureDetector(
                            onTap: () => setState(() => r.done = !r.done),
                            child: Icon(
                                r.done
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: 14,
                                color: r.done
                                    ? t.accentColor
                                    : Colors.white38),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              r.text,
                              style: t.titleStyle.copyWith(
                                fontSize: 12,
                                decoration: r.done
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: r.done ? Colors.white38 : Colors.white,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () =>
                                setState(() => _list.removeAt(i)),
                            child: const Icon(Icons.close,
                                size: 11, color: Colors.white24),
                          ),
                        ]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Reminder {
  String text;
  bool done;
  _Reminder(this.text, this.done);
}