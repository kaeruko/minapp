import 'package:shared_preferences/shared_preferences.dart';

const String girlsCurrentGroupPreferenceKey = 'girls_current_group_id';

abstract interface class GirlsCurrentGroupStore {
  Future<String?> load();
  Future<void> save(String groupId);
  Future<void> clear();
}

class SharedPreferencesGirlsCurrentGroupStore
    implements GirlsCurrentGroupStore {
  const SharedPreferencesGirlsCurrentGroupStore();

  Future<SharedPreferences> _preferences() => SharedPreferences.getInstance();

  @override
  Future<String?> load() async {
    final SharedPreferences preferences = await _preferences();
    final String? groupId = preferences.getString(girlsCurrentGroupPreferenceKey);
    if (groupId == null) return null;
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(groupId)) {
      throw const FormatException('Stored Girls current group id is invalid.');
    }
    return groupId;
  }

  @override
  Future<void> save(String groupId) async {
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(groupId)) {
      throw const FormatException('Girls current group id is invalid.');
    }
    final SharedPreferences preferences = await _preferences();
    final bool stored = await preferences.setString(
      girlsCurrentGroupPreferenceKey,
      groupId,
    );
    if (!stored) {
      throw StateError('Could not persist the Girls current group id.');
    }
  }

  @override
  Future<void> clear() async {
    final SharedPreferences preferences = await _preferences();
    final bool removed = await preferences.remove(girlsCurrentGroupPreferenceKey);
    if (!removed && preferences.containsKey(girlsCurrentGroupPreferenceKey)) {
      throw StateError('Could not clear the Girls current group id.');
    }
  }
}
