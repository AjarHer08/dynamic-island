import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../providers/tasks_provider.dart';
import '../../theme/island_theme.dart';
import '../../utils/tr.dart';
import '../liquid_glass.dart';
import '../live_clock.dart';

/// Panel Tugas: tulis pekerjaan baru, ketuk kotak untuk mencoret.
class TasksPanel extends StatefulWidget {
  const TasksPanel({super.key});

  @override
  State<TasksPanel> createState() => _TasksPanelState();
}

class _TasksPanelState extends State<TasksPanel> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _add() {
    final text = _ctrl.text;
    if (text.trim().isEmpty) return;
    context.read<TasksProvider>().add(text);
    _ctrl.clear();
  }

  /// "03:25:42" untuk hari ini, "08/11 03:25:42" untuk hari lain.
  static String _stamp(DateTime d) {
    final now = DateTime.now();
    final time =
        '${twoDigits(d.hour)}:${twoDigits(d.minute)}:${twoDigits(d.second)}';
    final today = d.year == now.year && d.month == now.month && d.day == now.day;
    return today ? time : '${twoDigits(d.day)}/${twoDigits(d.month)} $time';
  }

  Widget _checkbox(TaskItem it, IslandTheme t, Color onAccent) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.read<TasksProvider>().toggle(it.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: it.done ? t.accentColor : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
              color: it.done ? t.accentColor : Colors.white54, width: 1.6),
        ),
        child: it.done ? Icon(Icons.check, size: 16, color: onAccent) : null,
      ),
    );
  }

  Widget _row(TaskItem it, IslandTheme t, Color onAccent) {
    final meta = it.done
        ? tr(context, 'Dibuat ${_stamp(it.createdAt)}  ·  Selesai ${_stamp(it.doneAt!)}',
            'Created ${_stamp(it.createdAt)}  ·  Done ${_stamp(it.doneAt!)}')
        : tr(context, 'Dibuat ${_stamp(it.createdAt)}',
            'Created ${_stamp(it.createdAt)}');
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: cardDecoration(t, radius: 14),
      child: Row(children: [
        _checkbox(it, t, onAccent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              it.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.25,
                color: it.done ? Colors.white54 : Colors.white,
                decoration: it.done ? TextDecoration.lineThrough : null,
                decorationColor: it.done ? t.accentColor : null,
                decorationThickness: 2,
              ),
            ),
            const SizedBox(height: 3),
            Text(meta,
                style: t.subtitleStyle.copyWith(
                    fontSize: 9.5,
                    color: it.done
                        ? t.accentColor.withValues(alpha: 0.9)
                        : null)),
          ]),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.read<TasksProvider>().remove(it.id),
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.close, size: 15, color: Colors.white38),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasks = context.watch<TasksProvider>();
    final t = context.watch<SettingsProvider>().theme;
    final onAccent =
        t.accentColor.computeLuminance() > 0.6 ? Colors.black87 : Colors.white;
    final items = tasks.items;
    OutlineInputBorder border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c, width: 1));

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              cursorColor: t.accentColor,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _add(),
              decoration: InputDecoration(
                hintText: tr(context, 'Tambah pekerjaan baru...',
                    'Add a new task...'),
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                isDense: true,
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.25),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                border: border(Colors.white.withValues(alpha: 0.12)),
                enabledBorder: border(Colors.white.withValues(alpha: 0.12)),
                focusedBorder: border(t.accentColor.withValues(alpha: 0.7)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _add,
            child: Container(
              width: 46,
              height: 40,
              decoration: BoxDecoration(
                color: t.accentColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: t.accentColor.withValues(alpha: 0.35),
                      blurRadius: 8)
                ],
              ),
              child: Icon(Icons.add, size: 22, color: onAccent),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Text(
              tr(context, '${tasks.openCount} belum  ·  ${tasks.doneCount} selesai',
                  '${tasks.openCount} open  ·  ${tasks.doneCount} done'),
              style: t.subtitleStyle),
          const Spacer(),
          if (tasks.doneCount > 0)
            GestureDetector(
              onTap: tasks.clearDone,
              child: Text(tr(context, 'Hapus yang selesai', 'Clear done'),
                  style: t.subtitleStyle.copyWith(
                      fontSize: 10, color: t.accentColor)),
            ),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                      tr(context, 'Belum ada pekerjaan.\nKetik di atas lalu tekan +',
                          'No tasks yet.\nType above, then press +'),
                      textAlign: TextAlign.center,
                      style: t.subtitleStyle))
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _row(items[i], t, onAccent),
                ),
        ),
      ]),
    );
  }
}
