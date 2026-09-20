import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const String _builtInStatePreferencePrefix = 'builtin_state_v1';
final RegExp _builtInAppIdPattern = RegExp(r'^[a-z0-9_-]{1,64}$');
final RegExp _builtInStateKeyPattern = RegExp(r'^[A-Za-z0-9._:-]{1,128}$');

String builtInStatePreferenceKey(String appId, String key) {
  if (!_builtInAppIdPattern.hasMatch(appId)) {
    throw ArgumentError.value(
      appId,
      'appId',
      'must be a lowercase built-in app id',
    );
  }
  if (!_builtInStateKeyPattern.hasMatch(key)) {
    throw ArgumentError.value(
      key,
      'key',
      'must be a valid built-in state key',
    );
  }
  return '$_builtInStatePreferencePrefix::$appId::$key';
}

class BuiltInStateValue {
  const BuiltInStateValue({required this.found, this.value});

  final bool found;
  final Object? value;
}

/// Device-local built-in saves, independent of WebView cache and page lifetime.
///
/// All pages use [builtInStateStore], so reopening waits for accepted writes.
/// The legacy preferences backend and keys are retained to preserve old saves.
class BuiltInStateStore {
  BuiltInStateStore({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferencesLoader;
  Future<void>? _pending;

  Future<BuiltInStateValue> get(String appId, String key) {
    final String preferenceKey = builtInStatePreferenceKey(appId, key);
    return _enqueue(() async {
      final SharedPreferences preferences = await _preferencesLoader();
      // Legacy setters update their Dart cache even when the platform write
      // fails. Read platform state instead of treating that cache as a save.
      await preferences.reload();
      final String? rawValue = preferences.getString(preferenceKey);
      if (rawValue == null) {
        return const BuiltInStateValue(found: false);
      }
      try {
        return BuiltInStateValue(found: true, value: jsonDecode(rawValue));
      } on FormatException catch (error) {
        throw StateError(
          'Stored built-in state is not valid JSON for $key: $error',
        );
      }
    });
  }

  Future<void> set(String appId, String key, Object? value) {
    final String preferenceKey = builtInStatePreferenceKey(appId, key);
    // Snapshot now, before waiting for earlier operations. Callers may mutate
    // their state again while this write is queued.
    final String encoded = jsonEncode(value);
    return _enqueue(() async {
      final SharedPreferences preferences = await _preferencesLoader();
      final bool stored = await preferences.setString(preferenceKey, encoded);
      if (!stored) {
        throw StateError(
          'SharedPreferences refused to store built-in state for $key.',
        );
      }
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final Future<T> result =
        (_pending ?? Future<void>.value()).then((_) => operation());
    // Report the original error to its caller without blocking later requests.
    // Release an idle tail so the shared store does not retain the zone from
    // an earlier page or attach new requests to that completed future.
    late final Future<void> tail;
    void release() {
      if (identical(_pending, tail)) _pending = null;
    }

    tail = result.then<void>(
      (_) => release(),
      onError: (Object error, StackTrace stackTrace) => release(),
    );
    _pending = tail;
    return result;
  }
}

final BuiltInStateStore builtInStateStore = BuiltInStateStore();
