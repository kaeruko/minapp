import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';

final RegExp _idPattern = RegExp(r'^[0-9a-f]{32}$');
final RegExp _runtimeTokenPattern = RegExp(r'^[A-Za-z0-9_-]{32,64}$');
final RegExp _publishedContentPathPattern = RegExp(
  r'^/hosted/content/[A-Za-z0-9_-]{32,128}/index\.html$',
);
final RegExp _previewContentPathPattern = RegExp(
  r'^/hosted/preview/[A-Za-z0-9_-]{32,128}/index\.html$',
);

class GirlsAppTestSession {
  const GirlsAppTestSession({
    required this.contentUri,
    required this.contentExpiresIn,
    required this.runtimeToken,
    required this.runtimeExpiresIn,
    required this.sourceRevision,
    required this.publishedVersion,
  });

  final Uri contentUri;
  final int contentExpiresIn;
  final String runtimeToken;
  final int runtimeExpiresIn;
  final int? sourceRevision;
  final int? publishedVersion;

  bool get isDraftPreview => sourceRevision != null;
}

class GirlsAppPreviewApi {
  GirlsAppPreviewApi({required Uri baseUri, http.Client? client})
      : _baseUri = _validateBaseUri(baseUri),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final Uri _baseUri;
  final http.Client _client;
  final bool _ownsClient;

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<GirlsAppTestSession> createPublishedTest({
    required String accessToken,
    required String groupId,
    required String appId,
  }) async {
    _validateToken(accessToken);
    _validateId(groupId, 'groupId');
    _validateId(appId, 'appId');

    final Map<String, Object?> content = await _postEmpty(
      path: '/hosted/groups/$groupId/apps/$appId/published-session',
      accessToken: accessToken,
    );
    _requireExactFields(
      content,
      const <String>{'content_path', 'published_version', 'expires_in'},
      'Published test session response',
    );
    final String contentPath = _requiredString(content, 'content_path');
    if (!_publishedContentPathPattern.hasMatch(contentPath)) {
      throw const FormatException(
        'Published test session returned an invalid content path.',
      );
    }
    final int publishedVersion = _requiredPositiveInt(
      content,
      'published_version',
    );
    final int contentExpiresIn = _requiredPositiveInt(content, 'expires_in');

    final _RuntimeSession runtime = await _createRuntimeSession(
      accessToken: accessToken,
      groupId: groupId,
      appId: appId,
    );
    return GirlsAppTestSession(
      contentUri: _baseUri.resolve(contentPath),
      contentExpiresIn: contentExpiresIn,
      runtimeToken: runtime.token,
      runtimeExpiresIn: runtime.expiresIn,
      sourceRevision: null,
      publishedVersion: publishedVersion,
    );
  }

  Future<GirlsAppTestSession> createDraftPreview({
    required String accessToken,
    required String groupId,
    required String appId,
  }) async {
    _validateToken(accessToken);
    _validateId(groupId, 'groupId');
    _validateId(appId, 'appId');

    final Map<String, Object?> content = await _postEmpty(
      path: '/hosted/my/apps/$appId/preview-session',
      accessToken: accessToken,
    );
    _requireExactFields(
      content,
      const <String>{
        'app_id',
        'group_id',
        'source_revision',
        'content_path',
        'expires_in',
      },
      'Draft preview session response',
    );
    if (_requiredString(content, 'app_id') != appId ||
        _requiredString(content, 'group_id') != groupId) {
      throw const FormatException(
        'Draft preview session returned a different app or group.',
      );
    }
    final int sourceRevision = _requiredPositiveInt(
      content,
      'source_revision',
    );
    final String contentPath = _requiredString(content, 'content_path');
    if (!_previewContentPathPattern.hasMatch(contentPath)) {
      throw const FormatException(
        'Draft preview session returned an invalid content path.',
      );
    }
    final int contentExpiresIn = _requiredPositiveInt(content, 'expires_in');

    final _RuntimeSession runtime = await _createRuntimeSession(
      accessToken: accessToken,
      groupId: groupId,
      appId: appId,
    );
    return GirlsAppTestSession(
      contentUri: _baseUri.resolve(contentPath),
      contentExpiresIn: contentExpiresIn,
      runtimeToken: runtime.token,
      runtimeExpiresIn: runtime.expiresIn,
      sourceRevision: sourceRevision,
      publishedVersion: null,
    );
  }

  Future<_RuntimeSession> _createRuntimeSession({
    required String accessToken,
    required String groupId,
    required String appId,
  }) async {
    final Map<String, Object?> payload = await _postEmpty(
      path: '/hosted/groups/$groupId/apps/$appId/runtime-session',
      accessToken: accessToken,
    );
    _requireExactFields(
      payload,
      const <String>{'token', 'expires_in'},
      'Runtime test session response',
    );
    final String token = _requiredString(payload, 'token');
    if (!_runtimeTokenPattern.hasMatch(token)) {
      throw const FormatException(
        'Runtime test session returned an invalid token.',
      );
    }
    return _RuntimeSession(
      token: token,
      expiresIn: _requiredPositiveInt(payload, 'expires_in'),
    );
  }

  Future<Map<String, Object?>> _postEmpty({
    required String path,
    required String accessToken,
  }) async {
    if (!path.startsWith('/')) {
      throw ArgumentError.value(path, 'path', 'must start with /.');
    }
    final http.Response response = await _client.post(
      _baseUri.resolve(path),
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: '{}',
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
      _requireExactFields(
        decoded,
        const <String>{'error', 'message'},
        'API error response',
      );
      final Object? error = decoded['error'];
      final Object? message = decoded['message'];
      if (error is! String ||
          error.isEmpty ||
          message is! String ||
          message.isEmpty) {
        throw const FormatException(
          'API error response is missing error or message.',
        );
      }
      throw ApiException(
        statusCode: response.statusCode,
        code: error,
        message: message,
      );
    }
    return decoded;
  }
}

class _RuntimeSession {
  const _RuntimeSession({required this.token, required this.expiresIn});

  final String token;
  final int expiresIn;
}

Uri _validateBaseUri(Uri uri) {
  if (uri.scheme != 'https' ||
      !uri.hasAuthority ||
      uri.userInfo.isNotEmpty ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw ArgumentError.value(
      uri,
      'baseUri',
      'must be an HTTPS origin without credentials, path, query, or fragment',
    );
  }
  return uri;
}

void _validateToken(String accessToken) {
  if (accessToken.isEmpty) {
    throw ArgumentError.value(accessToken, 'accessToken', 'must not be empty');
  }
}

void _validateId(String value, String label) {
  if (!_idPattern.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      label,
      'must be a 32-character lowercase hexadecimal ID',
    );
  }
}

String _requiredString(Map<String, Object?> payload, String key) {
  final Object? value = payload[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value;
}

int _requiredPositiveInt(Map<String, Object?> payload, String key) {
  final Object? value = payload[key];
  if (value is! int || value < 1) {
    throw FormatException('$key must be a positive integer.');
  }
  return value;
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
