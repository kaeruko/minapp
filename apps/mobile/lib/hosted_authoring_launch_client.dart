import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';

final RegExp _authoringLaunchIdPattern = RegExp(r'^[0-9a-f]{32}$');
final RegExp _authoringLaunchTokenPattern = RegExp(r'^[A-Za-z0-9_-]{32,64}$');
final RegExp _authoringEditorPathPattern = RegExp(
  r'^/hosted/authoring-editor/([A-Za-z0-9_-]{32,64})/index\.html$',
);

class HostedAuthoringLaunchGrant {
  const HostedAuthoringLaunchGrant({
    required this.contentUri,
    required this.contentExpiresIn,
    required this.runtimeToken,
    required this.runtimeExpiresIn,
    required this.authoringToken,
    required this.authoringExpiresIn,
    required this.contentId,
    required this.contentFormat,
    required this.editorAppId,
    required this.allowedOperations,
  });

  final Uri contentUri;
  final int contentExpiresIn;
  final String runtimeToken;
  final int runtimeExpiresIn;
  final String authoringToken;
  final int authoringExpiresIn;
  final String contentId;
  final String contentFormat;
  final String editorAppId;
  final List<String> allowedOperations;
}

class HostedAuthoringLaunchApiClient {
  HostedAuthoringLaunchApiClient({required Uri baseUri, http.Client? client})
      : _baseUri = _validateBaseUri(baseUri),
        _client = client ?? http.Client();

  final Uri _baseUri;
  final http.Client _client;

  Future<HostedAuthoringLaunchGrant> createLaunch({
    required String accessToken,
    required String contentId,
    required String editorAppId,
  }) async {
    _validateAccessToken(accessToken);
    _validateId(contentId, 'contentId');
    _validateId(editorAppId, 'editorAppId');

    final Uri uri = _baseUri.resolve('/hosted/authoring/projects/$contentId/launch');
    final http.Response response = await _client.post(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, Object?>{'editor_app_id': editorAppId}),
    );
    final Map<String, Object?> payload = _decodeJsonObject(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiException(response.statusCode, payload);
    }

    _requireExactFields(
      payload,
      const <String>{
        'content_path',
        'content_expires_in',
        'runtime_token',
        'runtime_expires_in',
        'authoring_token',
        'authoring_expires_in',
        'content_id',
        'content_format',
        'editor_app_id',
        'allowed_operations',
      },
      'Authoring launch response',
    );

    final String returnedContentId = _requiredString(payload, 'content_id');
    final String returnedEditorAppId = _requiredString(payload, 'editor_app_id');
    if (returnedContentId != contentId || returnedEditorAppId != editorAppId) {
      throw const FormatException(
        'Authoring launch response changed the requested scope.',
      );
    }

    final String contentPath = _requiredString(payload, 'content_path');
    if (!_authoringEditorPathPattern.hasMatch(contentPath)) {
      throw const FormatException(
        'Authoring launch response returned an invalid Editor content path.',
      );
    }
    final Uri contentUri = _baseUri.resolve(contentPath);
    if (contentUri.query.isNotEmpty || contentUri.fragment.isNotEmpty) {
      throw const FormatException(
        'Authoring launch response returned an invalid Editor content URI.',
      );
    }

    final String runtimeToken = _requiredString(payload, 'runtime_token');
    final String authoringToken = _requiredString(payload, 'authoring_token');
    _validateCapabilityToken(runtimeToken, 'runtime_token');
    _validateCapabilityToken(authoringToken, 'authoring_token');

    return HostedAuthoringLaunchGrant(
      contentUri: contentUri,
      contentExpiresIn: _requiredPositiveInt(payload, 'content_expires_in'),
      runtimeToken: runtimeToken,
      runtimeExpiresIn: _requiredPositiveInt(payload, 'runtime_expires_in'),
      authoringToken: authoringToken,
      authoringExpiresIn: _requiredPositiveInt(payload, 'authoring_expires_in'),
      contentId: returnedContentId,
      contentFormat: _requiredString(payload, 'content_format'),
      editorAppId: returnedEditorAppId,
      allowedOperations: List<String>.unmodifiable(
        _requiredStringList(payload, 'allowed_operations'),
      ),
    );
  }

  static Map<String, Object?> _decodeJsonObject(http.Response response) {
    final String? contentType = response.headers['content-type'];
    if (contentType == null ||
        !contentType.toLowerCase().startsWith('application/json')) {
      throw FormatException(
        'Authoring launch API returned a non-JSON response (HTTP ${response.statusCode}).',
      );
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException(
        'Authoring launch API returned an unexpected JSON payload.',
      );
    }
    return decoded;
  }

  static ApiException _apiException(
    int statusCode,
    Map<String, Object?> payload,
  ) {
    _requireExactFields(
      payload,
      const <String>{'error', 'message'},
      'Authoring launch API error response',
    );
    return ApiException(
      statusCode: statusCode,
      code: _requiredString(payload, 'error'),
      message: _requiredString(payload, 'message'),
    );
  }
}

void _validateId(String value, String name) {
  if (!_authoringLaunchIdPattern.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      name,
      'must be a 32-character lowercase hexadecimal id',
    );
  }
}

void _validateAccessToken(String value) {
  if (value.isEmpty) {
    throw ArgumentError.value(value, 'accessToken', 'must not be empty');
  }
}

void _validateCapabilityToken(String value, String name) {
  if (!_authoringLaunchTokenPattern.hasMatch(value)) {
    throw FormatException('Authoring launch field $name has an invalid token format.');
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('JSON field $key must be a non-empty string.');
  }
  return value;
}

int _requiredPositiveInt(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! int || value is bool || value < 1) {
    throw FormatException('JSON field $key must be a positive integer.');
  }
  return value;
}

List<String> _requiredStringList(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! List<Object?> ||
      value.isEmpty ||
      value.any((Object? item) => item is! String || item.isEmpty)) {
    throw FormatException('JSON field $key must be a non-empty string list.');
  }
  final List<String> result = value.cast<String>();
  if (result.toSet().length != result.length) {
    throw FormatException('JSON field $key must not contain duplicates.');
  }
  return result;
}

void _requireExactFields(
  Map<String, Object?> json,
  Set<String> expected,
  String context,
) {
  final Set<String> actual = json.keys.toSet();
  if (actual.length != expected.length ||
      actual.difference(expected).isNotEmpty ||
      expected.difference(actual).isNotEmpty) {
    throw FormatException('$context has unexpected fields.');
  }
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
