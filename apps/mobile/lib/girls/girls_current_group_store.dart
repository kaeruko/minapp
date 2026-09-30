import 'package:shared_preferences/shared_preferences.dart';

const String girlsCurrentGroupPreferenceKey = 'girls_current_group_id';
const String girlsCurrentGroupAccountPreferenceKey =
    'girls_current_group_account_id';
const String girlsCurrentGroupPreferencePrefix = 'girls_current_group_id.';

final RegExp _girlsHexIdPattern = RegExp(r'^[0-9a-f]{32}$');

abstract interface class GirlsCurrentGroupStore {
  Future<String?> load();
  Future<void> save(String groupId);
  Future<void> clear();
}

abstract interface class GirlsCurrentGroupAccountScope {
  Future<void> activateAccount(String userId);
  Future<void> deactivateAccount();
}

class SharedPreferencesGirlsCurrentGroupStore
    implements GirlsCurrentGroupStore, GirlsCurrentGroupAccountScope {
  const SharedPreferencesGirlsCurrentGroupStore();

  Future<SharedPreferences> _preferences() => SharedPreferences.getInstance();

  String _groupKey(String userId) => '$girlsCurrentGroupPreferencePrefix$userId';

  void _validateHexId(String value, String context) {
    if (!_girlsHexIdPattern.hasMatch(value)) {
      throw FormatException('$context must be a 32-character lowercase hex id.');
    }
  }

  Future<String> _activeUserId(SharedPreferences preferences) async {
    final String? userId =
        preferences.getString(girlsCurrentGroupAccountPreferenceKey);
    if (userId == null) {
      throw StateError('No active Girls account is selected.');
    }
    _validateHexId(userId, 'Stored Girls active user id');
    return userId;
  }

  @override
  Future<void> activateAccount(String userId) async {
    _validateHexId(userId, 'Girls user id');
    final SharedPreferences preferences = await _preferences();
    final bool stored = await preferences.setString(
      girlsCurrentGroupAccountPreferenceKey,
      userId,
    );
    if (!stored) {
      throw StateError('Could not persist the active Girls account.');
    }
  }

  @override
  Future<void> deactivateAccount() async {
    final SharedPreferences preferences = await _preferences();
    final bool removed =
        await preferences.remove(girlsCurrentGroupAccountPreferenceKey);
    if (!removed &&
        preferences.containsKey(girlsCurrentGroupAccountPreferenceKey)) {
      throw StateError('Could not clear the active Girls account.');
    }
  }

  @override
  Future<String?> load() async {
    final SharedPreferences preferences = await _preferences();
    final String userId = await _activeUserId(preferences);
    final String? groupId = preferences.getString(_groupKey(userId));
    if (groupId == null) return null;
    _validateHexId(groupId, 'Stored Girls current group id');
    return groupId;
  }

  @override
  Future<void> save(String groupId) async {
    _validateHexId(groupId, 'Girls current group id');
    final SharedPreferences preferences = await _preferences();
    final String userId = await _activeUserId(preferences);
    final bool stored = await preferences.setString(
      _groupKey(userId),
      groupId,
    );
    if (!stored) {
      throw StateError('Could not persist the Girls current group id.');
    }
  }

  @override
  Future<void> clear() async {
    final SharedPreferences preferences = await _preferences();
    final String userId = await _activeUserId(preferences);
    final String key = _groupKey(userId);
    final bool removed = await preferences.remove(key);
    if (!removed && preferences.containsKey(key)) {
      throw StateError('Could not clear the Girls current group id.');
    }
  }
}
