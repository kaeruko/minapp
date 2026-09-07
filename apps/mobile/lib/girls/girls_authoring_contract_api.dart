import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';

final RegExp _authoringIdPattern = RegExp(r'^[0-9a-f]{32}$');
final RegExp _contentFormatPattern = RegExp(
  r'^[a-z0-9][a-z0-9._-]{0,63}/[a-z0-9][a-z0-9._-]{0,63}@[1-9][0-9]{0,5}$',
);

class GirlsAuthoringAppContract {
  const GirlsAuthoringAppContract({
    required this.appId,
    required this.groupId,
    required this.title,
    required this.edits,
    required this.accepts,
  });

  final String appId;
  final String groupId;
  final String title;
  final List<String> edits;
  final List<String> accepts;

  bool editsFormat(String contentFormat) => edits.contains(contentFormat);
  bool acceptsFormat(String contentFormat) => accepts.contains(contentFormat);

  factory GirlsAuthoringAppContract.fromJson(Map<String, Object?> json) {
    _requireExactFields(
      json,
      const <String>{'app_id', 'group_id', 'title', 'edits', 'accepts'},
      'Authoring app contract',
    );
    final List<String> edits = _requiredFormats(json, 'edits');
    final List<String> accepts = _requiredFormats(json, 'accepts');
    if (edits.isEmpty && accepts.isEmpty) {
      throw const FormatException(
        'Authoring app contract must declare edits or accepts.',
      );
    }
    return GirlsAuthoringAppContract(
      appId: _requiredId(json, 'app_id'),
      groupId: _requiredId(json, 'group_id'),
      title: _requiredString(json, 'title'),
      edits: List<String>.unmodifiable(edits),
      accepts: List<String>.unmodifiable(accepts),
    );
  }
}

class GirlsAuthoringContractApi {
  GirlsAuthoringContractApi({required Uri baseUri, http.Client? client})
      : _baseUri = _validateBaseUri(baseUri),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final Uri _baseUri;
  final http.Client _client;
  final bool _ownsClient;

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<List<GirlsAuthoringAppContract>> listApps({
    required String accessToken,
    required String groupId,
  }) async {
    if (accessToken.isEmpty) {
      throw ArgumentError.value(accessToken, 'accessToken', 'must not be empty');
    }
    _validateId(groupId, 'groupId');

    final http.Response response = await _client.get(
      _baseUri.resolve('/hosted/authoring/groups/$groupId/apps'),
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    );
    final Map<String, Object?> payload = _decodeJsonResponse(response);
    _requireExactFields(
      payload,
      const <String>{'apps'},
      'Authoring apps response',
    );
    final Object? rawApps = payload['apps'];
    if (rawApps is! List<Object?>) {
      throw const FormatException('Authoring apps response has no apps list.');
    }

    final List<GirlsAuthoringAppContract> apps = <GirlsAuthoringAppContract>[];
    final Set<String> appIds = <String>{};
    for (final Object? rawApp in rawApps) {
      if (rawApp is! Map<String, Object?>) {
        throw const FormatException(
          'Authoring apps response contains a non-object app.',
        );
      }
      final GirlsAuthoringAppContract app =
          GirlsAuthoringAppContract.fromJson(rawApp);
      if (app.groupId != groupId) {
        throw const FormatException(
          'Authoring apps response changed the requested group scope.',
        );
      }
      if (!appIds.add(app.appId)) {
        throw const FormatException(
          'Authoring apps response contains a duplicate app_id.',
        );
      }
      apps.add(app);
    }
    return List<GirlsAuthoringAppContract>.unmodifiable(apps);
  }

  static Map<String, Object?> _decodeJsonResponse(http.Response response) {
    final String? contentType = response.headers['content-type'];
    if (contentType == null ||
        !contentType.toLowerCase().startsWith('application/json')) {
      throw FormatException(
        'Authoring API returned a non-JSON response (HTTP ${response.statusCode}).',
      );
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException(
        'Authoring API returned an unexpected JSON payload.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final Object? error = decoded['error'];
      final Object? message = decoded['message'];
      if (error is! String ||
          error.isEmpty ||
          message is! String ||
          message.isEmpty) {
        throw const FormatException(
          'Authoring API error response is missing error or message.',
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

List<String> _requiredFormats(Map<String, Object?> json, String key) {
  final Object? raw = json[key];
  if (raw is! List<Object?>) {
    throw FormatException('JSON field $key must be a list.');
  }
  final List<String> formats = <String>[];
  final Set<String> seen = <String>{};
  for (final Object? value in raw) {
    if (value is! String || !_contentFormatPattern.hasMatch(value)) {
      throw FormatException('JSON field $key contains an invalid content format.');
    }
    if (!seen.add(value)) {
      throw FormatException('JSON field $key contains a duplicate content format.');
    }
    formats.add(value);
  }
  return formats;
}

String _requiredId(Map<String, Object?> json, String key) {
  final String value = _requiredString(json, key);
  if (!_authoringIdPattern.hasMatch(value)) {
    throw FormatException('JSON field $key has an invalid ID.');
  }
  return value;
}

String _requiredString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('JSON field $key must be a non-empty string.');
  }
  return value;
}

void _validateId(String value, String label) {
  if (!_authoringIdPattern.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      label,
      'must be a 32-character lowercase hexadecimal ID',
    );
  }
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
