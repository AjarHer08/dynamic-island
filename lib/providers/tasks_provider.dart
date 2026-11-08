import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TaskItem {
  TaskItem({
    required this.id,
    required this.title,
    required this.createdAt,
    this.doneAt,
  });

  final String id;
  final String title;
  final DateTime createdAt;

  /// Waktu selesai (lengkap dengan detik). null = belum selesai.
  DateTime? doneAt;

  bool get done => doneAt != null;

  Map<String, dynamic> toJson() => {
        'i': id,
        't': title,
        'c': createdAt.millisecondsSinceEpoch,
        'd': doneAt?.millisecondsSinceEpoch,
      };

  static TaskItem? fromJson(dynamic j) {
    if (j is! Map) return null;
    final id = j['i'], t = j['t'], c = j['c'];
    if (id is! String || t is! String || c is! int) return null;
    final d = j['d'];
    return TaskItem(
      id: id,
      title: t,
      createdAt: DateTime.fromMillisecondsSinceEpoch(c),
      doneAt: d is int ? DateTime.fromMillisecondsSinceEpoch(d) : null,
    );
  }
}

/// Daftar pekerjaan: tambah, centang (dicoret + waktu selesai), hapus.
/// Disimpan di SharedPreferences sehingga tetap ada setelah aplikasi ditutup.
class TasksProvider extends ChangeNotifier {
  static const _key = 'tasks_v1';
  final List<TaskItem> _items = [];

  /// Belum selesai dulu (terbaru di atas), lalu yang sudah selesai
  /// (paling baru diselesaikan di atas).
  List<TaskItem> get items {
    final open = _items.where((e) => !e.done).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final done = _items.where((e) => e.done).toList()
      ..sort((a, b) => b.doneAt!.compareTo(a.doneAt!));
    return [...open, ...done];
  }

  int get openCount => _items.where((e) => !e.done).length;
  int get doneCount => _items.where((e) => e.done).length;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return;
      final j = jsonDecode(raw);
      if (j is! List) return;
      _items
        ..clear()
        ..addAll(j.map(TaskItem.fromJson).whereType<TaskItem>());
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode(_items.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  void add(String title) {
    final t = title.trim();
    if (t.isEmpty) return;
    final now = DateTime.now();
    _items.add(TaskItem(
        id: now.microsecondsSinceEpoch.toString(), title: t, createdAt: now));
    notifyListeners();
    _save();
  }

  /// Ketuk kotak: selesai (catat jam + detik) atau batalkan.
  void toggle(String id) {
    final i = _items.indexWhere((e) => e.id == id);
    if (i < 0) return;
    _items[i].doneAt = _items[i].done ? null : DateTime.now();
    notifyListeners();
    _save();
  }

  void remove(String id) {
    _items.removeWhere((e) => e.id == id);
    notifyListeners();
    _save();
  }

  void clearDone() {
    _items.removeWhere((e) => e.done);
    notifyListeners();
    _save();
  }
}
