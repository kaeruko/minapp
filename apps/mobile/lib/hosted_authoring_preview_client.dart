import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';

final RegExp _authoringPreviewIdPattern = RegExp(r'^[0-9a-f]{32}$');
final RegExp _authoringPreviewTokenPattern = RegExp(r'^[A-Za-z0-9_-]{32,64}$');
final RegExp _authoringPreviewPathPattern = RegExp(
  r'^/hosted/authoring-preview/([A-Za-z0-9_-]{32,64})/index\.html$',
);

class HostedAuthoringPreviewGrant {
  const HostedAuthoringPreviewGrant({
    required this.contentUri,
    required this.expiresIn,
    required this.runtimeToken,
    required this.runtimeExpiresIn,
    required this.contentId,
    required this.contentFormat,
    required this.draftRevision,
    required this.playerAppId,
  });

  final Uri contentUri;
  final int expiresIn;
  final String runtimeToken;
  final int runtimeExpiresIn;
  final String contentId;
  final String contentFormat;
  final int draftRevision;
  final String playerAppId;
}

class HostedAuthoringPreviewApiClient {
  HostedAuthoringPreviewApiClient({required Uri baseUri, http.Client? client})
      : _baseUri = _validateBaseUri(baseUri),
        _client = client ?? http.Client();

  final Uri _baseUri;
  final http.Client _client;

  Future<HostedAuthoringPreviewGrant> createPreview({
    required String accessToken,
    required String contentId,
    required String playerAppId,
    required int expectedRevision,
  }) async {
    _validateAccessToken(accessToken);
    _validateId(contentId, 'contentId');
    _validateId(playerAppId, 'playerAppId');
    if (expectedRevision < 1) {
      throw ArgumentError.value(
        expectedRevision,
        'expectedRevision',
        'must be a positive integer',
      );
    }

    final Uri uri = _baseUri.resolve('/hosted/authoring/projects/$contentId/preview');
    final http.Response response = await _client.post(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, Object?>{
        'player_app_id': playerAppId,
        'expected_revision': expectedRevision,
      }),
    );
    final Map<String, Object?> payload = _decodeJsonObject(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiException(response.statusCode, payload);
    }
    _requireExactFields(
      payload,
      const <String>{
        'content_id',
        'content_format',
        'draft_revision',
        'player_app_id',
        'content_path',
        'expires_in',
        'runtime_token',
        'runtime_expires_in',
      },
      'Authoring preview response',
    );

    final String returnedContentId = _requiredString(payload, 'content_id');
    final String returnedPlayerAppId = _requiredString(payload, 'player_app_id');
    final int returnedRevision = _requiredPositiveInt(payload, 'draft_revision');
    if (returnedContentId != contentId ||
        returnedPlayerAppId != playerAppId ||
        returnedRevision != expectedRevision) {
      throw const FormatException(
        'Authoring preview response changed the requested scope or revision.',
      );
    }

    final String contentPath = _requiredString(payload, 'content_path');
    if (!_authoringPreviewPathPattern.hasMatch(contentPath)) {
      throw const FormatException(
        'Authoring preview response returned an invalid content path.',
      );
    }
    final Uri contentUri = _baseUri.resolve(contentPath);
    if (contentUri.query.isNotEmpty || contentUri.fragment.isNotEmpty) {
      throw const FormatException(
        'Authoring preview response returned an invalid content URI.',
      );
    }
    final String runtimeToken = _requiredString(payload, 'runtime_token');
    _validateCapabilityToken(runtimeToken, 'runtime_token');

    return HostedAuthoringPreviewGrant(
      contentUri: contentUri,
      expiresIn: _requiredPositiveInt(payload, 'expires_in'),
      runtimeToken: runtimeToken,
      runtimeExpiresIn: _requiredPositiveInt(payload, 'runtime_expires_in'),
      contentId: returnedContentId,
      contentFormat: _requiredString(payload, 'content_format'),
      draftRevision: returnedRevision,
      playerAppId: returnedPlayerAppId,
    );
  }

  static Map<String, Object?> _decodeJsonObject(http.Response response) {
    final String? contentType = response.headers['content-type'];
    if (contentType == null ||
        !contentType.toLowerCase().startsWith('application/json')) {
      throw FormatException(
        'Authoring preview API returned a non-JSON response (HTTP ${response.statusCode}).',
      );
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException(
        'Authoring preview API returned an unexpected JSON payload.',
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
      'Authoring preview API error response',
    );
    return ApiException(
      statusCode: statusCode,
      code: _requiredString(payload, 'error'),
      message: _requiredString(payload, 'message'),
    );
  }
}

void _validateId(String value, String name) {
  if (!_authoringPreviewIdPattern.hasMatch(value)) {
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
  if (!_authoringPreviewTokenPattern.hasMatch(value)) {
    throw FormatException('Authoring preview field $name has an invalid token format.');
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
