import 'dart:convert';

import 'package:http/http.dart' as http;

sealed class AuthResult {
  const AuthResult();
}

class AuthenticatedSession extends AuthResult {
  const AuthenticatedSession({required this.accessToken, required this.expiresIn});

  final String accessToken;
  final int expiresIn;
}

class NewPasswordChallenge extends AuthResult {
  const NewPasswordChallenge({required this.loginId, required this.session});

  final String loginId;
  final String session;
}

class PublishedApp {
  const PublishedApp({
    required this.appId,
    required this.versionId,
    required this.groupId,
    required this.groupName,
    required this.ownerUserId,
    required this.ownerLoginId,
    required this.title,
    required this.reviewedAt,
    this.description,
  });

  final String appId;
  final String versionId;
  final String groupId;
  final String groupName;
  final String ownerUserId;
  // Kept as ownerLoginId for API compatibility; UI prefers owner_display_name when present.
  final String ownerLoginId;
  final String title;
  final DateTime reviewedAt;
  final String? description;

  factory PublishedApp.fromJson(Map<String, Object?> json) {
    final String status = _requiredString(json, 'status');
    if (status != 'approved') {
      throw const FormatException('Mobile catalog contained a non-approved app.');
    }
    return PublishedApp(
      appId: _requiredString(json, 'app_id'),
      versionId: _requiredString(json, 'version_id'),
      groupId: _requiredString(json, 'group_id'),
      groupName: _requiredString(json, 'group_name'),
      ownerUserId: _requiredHexId(json, 'owner_user_id'),
      ownerLoginId:
          _optionalDisplayName(json) ?? _requiredString(json, 'owner_login_id'),
      title: _requiredString(json, 'title'),
      reviewedAt: DateTime.parse(_requiredString(json, 'reviewed_at')).toUtc(),
      description: _optionalDescription(json),
    );
  }
}

class LaunchGrant {
  const LaunchGrant({required this.url, required this.expiresIn});

  final Uri url;
  final int expiresIn;
}

class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'ApiException($statusCode, $code, $message)';
}

abstract interface class MinAppApi {
  Future<AuthResult> login(String loginId, String password);

  Future<AuthenticatedSession> completeNewPassword({
    required String loginId,
    required String newPassword,
    required String session,
  });

  Future<List<PublishedApp>> listPublishedApps(String accessToken);

  Future<LaunchGrant> createLaunch(String accessToken, PublishedApp app);

  Future<void> reportApp(
    String accessToken,
    PublishedApp app,
    String reason,
  );
}

class MinAppApiClient implements MinAppApi {
  MinAppApiClient({required Uri baseUri, http.Client? client})
      : _baseUri = _validateBaseUri(baseUri),
        _client = client ?? http.Client();

  final Uri _baseUri;
  final http.Client _client;

  @override
  Future<AuthResult> login(String loginId, String password) async {
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'POST',
      path: '/auth/login',
      body: <String, Object?>{'login_id': loginId, 'password': password},
    );
    return _parseAuthResult(payload);
  }

  @override
  Future<AuthenticatedSession> completeNewPassword({
    required String loginId,
    required String newPassword,
    required String session,
  }) async {
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'POST',
      path: '/auth/change-password',
      body: <String, Object?>{
        'login_id': loginId,
        'new_password': newPassword,
        'session': session,
      },
    );
    final AuthResult result = _parseAuthResult(payload);
    if (result is! AuthenticatedSession) {
      throw const FormatException(
        'Password change returned another authentication challenge.',
      );
    }
    return result;
  }

  @override
  Future<List<PublishedApp>> listPublishedApps(String accessToken) async {
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'GET',
      path: '/mobile/apps',
      accessToken: accessToken,
    );
    final Object? rawApps = payload['apps'];
    if (rawApps is! List<Object?>) {
      throw const FormatException('Mobile catalog response has no apps list.');
    }
    return rawApps.map((Object? raw) {
      if (raw is! Map<String, Object?>) {
        throw const FormatException('Mobile catalog contains a non-object app.');
      }
      return PublishedApp.fromJson(raw);
    }).toList(growable: false);
  }

  @override
  Future<LaunchGrant> createLaunch(String accessToken, PublishedApp app) async {
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'POST',
      path: '/mobile/apps/${app.appId}/versions/${app.versionId}/launch',
      accessToken: accessToken,
      body: const <String, Object?>{},
    );
    final String rawUrl = _requiredString(payload, 'url');
    final Object? rawExpiresIn = payload['expires_in'];
    if (rawExpiresIn is! int || rawExpiresIn <= 0) {
      throw const FormatException('Launch response has invalid expires_in.');
    }
    final Uri url = Uri.parse(rawUrl);
    if (url.scheme != 'https' || !url.hasAuthority || url.fragment.isNotEmpty) {
      throw const FormatException('Launch URL must be an absolute HTTPS URL.');
    }
    if (url.pathSegments.length < 3 || url.pathSegments.first != 'launch') {
      throw const FormatException('Launch URL has an unexpected path.');
    }
    return LaunchGrant(url: url, expiresIn: rawExpiresIn);
  }

  @override
  Future<void> reportApp(
    String accessToken,
    PublishedApp app,
    String reason,
  ) async {
    if (reason.isEmpty || reason != reason.trim() || reason.length > 80) {
      throw ArgumentError.value(
        reason,
        'reason',
        'must be 1-80 trimmed characters',
      );
    }
    await _jsonRequest(
      method: 'POST',
      path: '/mobile/apps/${app.appId}/versions/${app.versionId}/reports',
      accessToken: accessToken,
      body: <String, Object?>{'reason': reason},
    );
  }

  Future<Map<String, Object?>> _jsonRequest({
    required String method,
    required String path,
    String? accessToken,
    Map<String, Object?>? body,
  }) async {
    if (!path.startsWith('/')) {
      throw ArgumentError.value(path, 'path', 'API path must start with /.');
    }
    final Uri uri = _baseUri.resolve(path);
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
    };
    if (accessToken != null) {
      if (accessToken.isEmpty) {
        throw ArgumentError.value(accessToken, 'accessToken', 'must not be empty');
      }
      headers['Authorization'] = 'Bearer $accessToken';
    }
    if (body != null) headers['Content-Type'] = 'application/json';

    late final http.Response response;
    if (method == 'GET') {
      if (body != null) throw ArgumentError('GET request must not contain a body.');
      response = await _client.get(uri, headers: headers);
    } else if (method == 'POST') {
      response = await _client.post(
        uri,
        headers: headers,
        body: body == null ? null : jsonEncode(body),
      );
    } else {
      throw ArgumentError.value(method, 'method', 'Unsupported HTTP method.');
    }

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
      throw ApiException(
        statusCode: response.statusCode,
        code: decoded['error'] is String ? decoded['error']! as String : 'api_error',
        message: decoded['message'] is String
            ? decoded['message']! as String
            : 'API request failed with HTTP ${response.statusCode}.',
      );
    }
    return decoded;
  }

  static AuthResult _parseAuthResult(Map<String, Object?> payload) {
    final String state = _requiredString(payload, 'state');
    if (state == 'new_password_required') {
      return NewPasswordChallenge(
        loginId: _requiredString(payload, 'login_id'),
        session: _requiredString(payload, 'session'),
      );
    }
    if (state == 'authenticated') {
      final Object? rawExpiresIn = payload['expires_in'];
      if (rawExpiresIn is! int || rawExpiresIn <= 0) {
        throw const FormatException('Authentication response has invalid expiry.');
      }
      return AuthenticatedSession(
        accessToken: _requiredString(payload, 'access_token'),
        expiresIn: rawExpiresIn,
      );
    }
    throw FormatException('Unsupported authentication state: $state');
  }

  static Uri _validateBaseUri(Uri uri) {
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
}

String _requiredString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('JSON field $key must be a non-empty string.');
  }
  return value;
}

String _requiredHexId(Map<String, Object?> json, String key) {
  final String value = _requiredString(json, key);
  if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(value)) {
    throw FormatException('JSON field $key must be a 32-character lowercase hexadecimal id.');
  }
  return value;
}

String? _optionalDisplayName(Map<String, Object?> json) {
  final Object? value = json['owner_display_name'];
  if (value == null) return null;
  if (value is! String ||
      value.isEmpty ||
      value.length > 40 ||
      value.trim() != value ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    throw const FormatException(
      'JSON field owner_display_name must be a trimmed non-empty string up to 40 characters when present.',
    );
  }
  return value;
}

String? _optionalDescription(Map<String, Object?> json) {
  final Object? value = json['description'];
  if (value == null) return null;
  if (value is! String || value.isEmpty || value.length > 200) {
    throw const FormatException(
      'JSON field description must be a non-empty string up to 200 characters when present.',
    );
  }
  return value;
}
