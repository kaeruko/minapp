import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class HostedSessionStore {
  Future<String?> readRefreshToken();
  Future<void> writeRefreshToken(String refreshToken);
  Future<void> clearRefreshToken();
}

class SecureHostedSessionStore implements HostedSessionStore {
  SecureHostedSessionStore({
    required String refreshTokenStorageKey,
    FlutterSecureStorage? storage,
  })  : _refreshTokenStorageKey = refreshTokenStorageKey,
        _storage = storage ?? const FlutterSecureStorage() {
    if (refreshTokenStorageKey.isEmpty) {
      throw ArgumentError.value(
        refreshTokenStorageKey,
        'refreshTokenStorageKey',
        'must not be empty',
      );
    }
  }

  final String _refreshTokenStorageKey;
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readRefreshToken() async {
    final String? refreshToken =
        await _storage.read(key: _refreshTokenStorageKey);
    if (refreshToken == null) return null;
    _validateRefreshToken(refreshToken, context: 'stored refresh token');
    return refreshToken;
  }

  @override
  Future<void> writeRefreshToken(String refreshToken) async {
    _validateRefreshToken(refreshToken, context: 'refresh token');
    await _storage.write(
      key: _refreshTokenStorageKey,
      value: refreshToken,
    );
  }

  @override
  Future<void> clearRefreshToken() {
    return _storage.delete(key: _refreshTokenStorageKey);
  }
}

void _validateRefreshToken(String value, {required String context}) {
  if (value.isEmpty || value.length > 8192) {
    throw FormatException(
      '$context must be a non-empty string no longer than 8192 characters.',
    );
  }
}
