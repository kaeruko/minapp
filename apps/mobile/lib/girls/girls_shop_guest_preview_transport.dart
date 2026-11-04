import 'dart:convert';
import 'dart:math';

import '../api.dart';
import '../hosted_runtime_bridge.dart';

/// Isolated, non-persistent state for one anonymous shop play session.
/// No state operation makes a network request or touches local device storage.
class GirlsGuestPreviewRuntimeTransport implements HostedRuntimeTransport {
  GirlsGuestPreviewRuntimeTransport() : runtimeToken = _newRuntimeToken();

  static const int _maxRequests = 300;
  static const int _maxKeys = 64;
  static const int _maxValueBytes = 16 * 1024;
  static const int _maxStorageBytes = 256 * 1024;

  final String runtimeToken;
  final Map<String, _GuestPreviewValue> _state = <String, _GuestPreviewValue>{};
  final Map<String, _GuestPreviewValue> _userState = <String, _GuestPreviewValue>{};
  int _requests = 0;
  bool _closed = false;

  static String _newRuntimeToken() {
    final Random random = Random.secure();
    final List<int> bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  void close() {
    _closed = true;
    _state.clear();
    _userState.clear();
  }

  void _validate(String token, String key) {
    if (_closed) {
      throw StateError('Guest shop preview session has ended.');
    }
    if (token != runtimeToken) {
      throw ArgumentError.value(token, 'runtimeToken', 'must match this preview session');
    }
    validateHostedStateKey(key);
    _requests += 1;
    if (_requests > _maxRequests) {
      throw const ApiException(
        statusCode: 429,
        code: 'runtime_request_limit_reached',
        message: 'このおためしプレイの操作上限に達しました。もう一度開いてください。',
      );
    }
  }

  Future<Object?> _get(
    Map<String, _GuestPreviewValue> store,
    String token,
    String key,
  ) async {
    _validate(token, key);
    final _GuestPreviewValue? item = store[key];
    if (item == null) {
      throw const ApiException(
        statusCode: 404,
        code: 'state_not_found',
        message: 'Preview state was not found.',
      );
    }
    return jsonDecode(jsonEncode(item.value));
  }

  Future<Object?> _set(
    Map<String, _GuestPreviewValue> store,
    String token,
    String key,
    Object? value,
  ) async {
    _validate(token, key);
    final String encoded = jsonEncode(value);
    final int bytes = utf8.encode(encoded).length;
    if (bytes > _maxValueBytes) {
      throw const ApiException(
        statusCode: 413,
        code: 'runtime_value_too_large',
        message: 'Runtime state values must be at most 16384 bytes.',
      );
    }
    if (!store.containsKey(key) && store.length >= _maxKeys) {
      throw const ApiException(
        statusCode: 409,
        code: 'runtime_key_limit_reached',
        message: 'おためしプレイの保存キー上限に達しました。',
      );
    }
    final int total = store.values.fold<int>(
      0,
      (int total, _GuestPreviewValue item) => total + item.bytes,
    );
    final int previous = store[key]?.bytes ?? 0;
    if (total - previous + bytes > _maxStorageBytes) {
      throw const ApiException(
        statusCode: 413,
        code: 'runtime_storage_limit_reached',
        message: 'おためしプレイの一時保存容量を超えました。',
      );
    }
    final Object? snapshot = jsonDecode(encoded);
    store[key] = _GuestPreviewValue(snapshot, bytes);
    return jsonDecode(encoded);
  }

  Future<void> _delete(
    Map<String, _GuestPreviewValue> store,
    String token,
    String key,
  ) async {
    _validate(token, key);
    if (!store.containsKey(key)) {
      throw const ApiException(
        statusCode: 404,
        code: 'state_not_found',
        message: 'Preview state was not found.',
      );
    }
    store.remove(key);
  }

  @override
  Future<Object?> getState(String runtimeToken, String key) =>
      _get(_state, runtimeToken, key);

  @override
  Future<Object?> setState(String runtimeToken, String key, Object? value) =>
      _set(_state, runtimeToken, key, value);

  @override
  Future<void> deleteState(String runtimeToken, String key) =>
      _delete(_state, runtimeToken, key);

  @override
  Future<Object?> getUserState(String runtimeToken, String key) =>
      _get(_userState, runtimeToken, key);

  @override
  Future<Object?> setUserState(String runtimeToken, String key, Object? value) =>
      _set(_userState, runtimeToken, key, value);

  @override
  Future<void> deleteUserState(String runtimeToken, String key) =>
      _delete(_userState, runtimeToken, key);
}

class _GuestPreviewValue {
  const _GuestPreviewValue(this.value, this.bytes);

  final Object? value;
  final int bytes;
}
