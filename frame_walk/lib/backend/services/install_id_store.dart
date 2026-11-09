import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

// A random ID created the first time it's needed and kept for the life of the
// app install. It identifies which install produced a photo link without
// reading any hardware identifier.
class InstallIdStore {
  static const _key = 'framewalk.installId';

  String? _cached;

  Future<String> read() async {
    final cached = _cached;
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_key);
    if (id == null) {
      id = _generateId();
      await prefs.setString(_key, id);
    }
    return _cached = id;
  }

  static String _generateId() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
