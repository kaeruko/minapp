import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';

sealed class RefreshableAuthResult {
  const RefreshableAuthResult();
}

class RefreshableAuthenticatedResult extends RefreshableAuthResult {
  const RefreshableAuthenticatedResult({
    required this.accessToken,
    required this.expiresIn,
    required this.refreshToken,
  });

  final String accessToken;
  final int expiresIn;
  final String refreshToken;

  AuthenticatedSession toSession() => AuthenticatedSession(
        accessToken: accessToken,
        expiresIn: expiresIn,
      );
}

class RefreshablePasswordChallenge extends RefreshableAuthResult {
  const RefreshablePasswordChallenge({
    required this.loginId,
    required this.session,
  });

  final String loginId;
  final String session;

  NewPasswordChallenge toChallenge() => NewPasswordChallenge(
        loginId: loginId,
        session: session,
      );
}

/// Authentication client for shells that need to keep a Cognito refresh token.
///
/// Refresh tokens must remain in the trusted native shell. They are deliberately
/// not added to [AuthenticatedSession], which is passed throughout the mobile UI
/// and may eventually be used to create scoped Runtime/Authoring sessions.
class RefreshableAuthClient {
  RefreshableAuthClient({required Uri baseUri, http.Client? client})
      : _baseUri = _validateBaseUri(baseUri),
        _client = client ?? http.Client();

  final Uri _baseUri;
  final http.Client _client;

  Future<RefreshableAuthResult> login(String loginId, String password) async {
    if (loginId.isEmpty) {
      throw ArgumentError.value(loginId, 'loginId', 'must not be empty');
    }
    if (password.isEmpty) {
      throw ArgumentError.value(password, 'password', 'must not be empty');
    }
    final Map<String, Object?> payload = await _postJson(
      '/auth/login',
      <String, Object?>{
        'login_id': loginId,
        'password': password,
      },
    );
    return _parseLogin(payload);
  }

  Future<RefreshableAuthenticatedResult> refresh(String refreshToken) async {
    _validateRefreshToken(refreshToken);
    final Map<String, Object?> payload = await _postJson(
      '/auth/refresh',
      <String, Object?>{'refresh_token': refreshToken},
    );
    _requireExactFields(
      payload,
      const <String>{'state', 'access_token', 'token_type', 'expires_in'},
      'Refresh response',
    );
    final String state = _requiredString(payload, 'state');
    if (state != 'authenticated') {
      throw FormatException('Refresh response has unsupported state: $state');
    }
    _requireBearer(payload);
    return RefreshableAuthenticatedResult(
      accessToken: _requiredString(payload, 'access_token'),
      expiresIn: _requiredPositiveInt(payload, 'expires_in'),
      refreshToken: refreshToken,
    );
  }

  Future<Map<String, Object?>> _postJson(
    String path,
    Map<String, Object?> body,
  ) async {
    if (!path.startsWith('/')) {
      throw ArgumentError.value(path, 'path', 'API path must start with /.');
    }
    final http.Response response = await _client.post(
      _baseUri.resolve(path),
      headers: const <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    final String? contentType = response.headers['content-type'];
    if (contentType == null ||
        !contentType.toLowerCase().startsWith('application/json')) {
      throw FormatException(
        'API returned a non-JSON response (HTTP ${response.statusCode}).',
      );
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('API returned an unexpected JSON payload.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final Object? code = decoded['error'];
      final Object? message = decoded['message'];
      if (code is! String ||
          code.isEmpty ||
          message is! String ||
          message.isEmpty) {
        throw const FormatException(
          'API error response is missing error or message.',
        );
      }
      throw ApiException(
        statusCode: response.statusCode,
        code: code,
        message: message,
      );
    }
    return decoded;
  }

  RefreshableAuthResult _parseLogin(Map<String, Object?> payload) {
    final String state = _requiredString(payload, 'state');
    if (state == 'new_password_required') {
      _requireExactFields(
        payload,
        const <String>{'state', 'login_id', 'session'},
        'Login challenge response',
      );
      return RefreshablePasswordChallenge(
        loginId: _requiredString(payload, 'login_id'),
        session: _requiredString(payload, 'session'),
      );
    }
    if (state == 'authenticated') {
      _requireExactFields(
        payload,
        const <String>{
          'state',
          'access_token',
          'token_type',
          'expires_in',
          'refresh_token',
        },
        'Login response',
      );
      _requireBearer(payload);
      final String refreshToken = _requiredString(payload, 'refresh_token');
      _validateRefreshToken(refreshToken);
      return RefreshableAuthenticatedResult(
        accessToken: _requiredString(payload, 'access_token'),
        expiresIn: _requiredPositiveInt(payload, 'expires_in'),
        refreshToken: refreshToken,
      );
    }
    throw FormatException('Unsupported authentication state: $state');
  }
}

void _requireBearer(Map<String, Object?> payload) {
  if (_requiredString(payload, 'token_type') != 'Bearer') {
    throw const FormatException('Authentication token_type must be Bearer.');
  }
}

int _requiredPositiveInt(Map<String, Object?> payload, String key) {
  final Object? value = payload[key];
  if (value is! int || value is bool || value <= 0) {
    throw FormatException('JSON field $key must be a positive integer.');
  }
  return value;
}

String _requiredString(Map<String, Object?> payload, String key) {
  final Object? value = payload[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('JSON field $key must be a non-empty string.');
  }
  return value;
}

void _validateRefreshToken(String refreshToken) {
  if (refreshToken.isEmpty || refreshToken.length > 8192) {
    throw ArgumentError.value(
      refreshToken,
      'refreshToken',
      'must be a non-empty string no longer than 8192 characters',
    );
  }
}

void _requireExactFields(
  Map<String, Object?> payload,
  Set<String> expected,
  String context,
) {
  final Set<String> actual = payload.keys.toSet();
  if (actual.length != expected.length || !actual.containsAll(expected)) {
    throw FormatException(
      '$context fields mismatch. Expected ${expected.join(', ')}, got ${actual.join(', ')}.',
    );
  }
}

Uri _validateBaseUri(Uri uri) {
  if (uri.scheme != 'https' ||
      !uri.hasAuthority ||
      uri.userInfo.isNotEmpty ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty) {
    throw ArgumentError.value(
      uri,
      'baseUri',
      'API base URI must be an absolute HTTPS URL without credentials, query, or fragment.',
    );
  }
  return uri;
}
