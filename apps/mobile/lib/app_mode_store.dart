import 'package:shared_preferences/shared_preferences.dart';

enum MinAppLaunchMode { hosted, classroom }

abstract interface class MinAppLaunchModeStore {
  Future<MinAppLaunchMode?> load();
  Future<void> save(MinAppLaunchMode mode);
  Future<void> clear();
}

class SharedPreferencesMinAppLaunchModeStore implements MinAppLaunchModeStore {
  static const String _key = 'minapp.launch_mode.v1';

  @override
  Future<MinAppLaunchMode?> load() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final String? raw = preferences.getString(_key);
    if (raw == null) return null;
    switch (raw) {
      case 'hosted':
        return MinAppLaunchMode.hosted;
      case 'classroom':
        return MinAppLaunchMode.classroom;
      default:
        throw FormatException('Stored MinApp launch mode is invalid: $raw');
    }
  }

  @override
  Future<void> save(MinAppLaunchMode mode) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final String value = switch (mode) {
      MinAppLaunchMode.hosted => 'hosted',
      MinAppLaunchMode.classroom => 'classroom',
    };
    final bool saved = await preferences.setString(_key, value);
    if (!saved) throw StateError('Failed to persist MinApp launch mode.');
  }

  @override
  Future<void> clear() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final bool removed = await preferences.remove(_key);
    if (!removed && preferences.containsKey(_key)) {
      throw StateError('Failed to remove MinApp launch mode.');
    }
  }
}
