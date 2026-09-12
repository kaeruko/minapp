import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class GirlsSessionStore {
  Future<String?> readRefreshToken();
  Future<void> writeRefreshToken(String refreshToken);
  Future<void> clearRefreshToken();
}

class SecureGirlsSessionStore implements GirlsSessionStore {
  SecureGirlsSessionStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _refreshTokenKey = 'minapp.girls.refresh_token.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readRefreshToken() async {
    final String? refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null) return null;
    _validateRefreshToken(refreshToken, context: 'stored refresh token');
    return refreshToken;
  }

  @override
  Future<void> writeRefreshToken(String refreshToken) async {
    _validateRefreshToken(refreshToken, context: 'refresh token');
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  @override
  Future<void> clearRefreshToken() {
    return _storage.delete(key: _refreshTokenKey);
  }
}

void _validateRefreshToken(String value, {required String context}) {
  if (value.isEmpty || value.length > 8192) {
    throw FormatException(
      '$context must be a non-empty string no longer than 8192 characters.',
    );
  }
}
