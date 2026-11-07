import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DndProvider extends ChangeNotifier {
  bool _enabled = false;
  bool get enabled => _enabled;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _enabled = p.getBool('dnd') ?? false;
    notifyListeners();
  }

  Future<void> toggle() async {
    _enabled = !_enabled;
    final p = await SharedPreferences.getInstance();
    await p.setBool('dnd', _enabled);
    notifyListeners();
  }
}