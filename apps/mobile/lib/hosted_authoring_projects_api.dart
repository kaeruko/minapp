import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';

final RegExp _authoringProjectIdPattern = RegExp(r'^[0-9a-f]{32}$');
final RegExp _authoringContentFormatPattern = RegExp(
  r'^[a-z0-9][a-z0-9._-]{0,63}/[a-z0-9][a-z0-9._-]{0,63}@[1-9][0-9]{0,5}$',
);

class HostedAuthoringProjectSummary {
  const HostedAuthoringProjectSummary({
    required this.contentId,
    required this.groupId,
    required this.contentFormat,
    required this.status,
    required this.draftRevision,
    required this.createdAt,
    required this.updatedAt,
  });

  final String contentId;
  final String groupId;
  final String contentFormat;
  final String status;
  final int draftRevision;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory HostedAuthoringProjectSummary.fromJson(Map<String, Object?> json) {
    _requireExactFields(
      json,
      const <String>{
        'content_id',
        'group_id',
        'content_format',
        'status',
        'draft_revision',
        'assets',
        'created_at',
        'updated_at',
      },
      'Authoring project summary',
    );
    final String contentFormat = _requiredString(json, 'content_format');
    _validateContentFormat(contentFormat, 'content_format');
    final String status = _requiredString(json, 'status');
    if (status != 'draft') {
      throw FormatException(
        'Authoring project response returned unsupported status $status.',
      );
    }
    final Object? assets = json['assets'];
    if (assets is! List<Object?>) {
      throw const FormatException('Authoring project assets must be a list.');
    }
    return HostedAuthoringProjectSummary(
      contentId: _requiredId(json, 'content_id'),
      groupId: _requiredId(json, 'group_id'),
      contentFormat: contentFormat,
      status: status,
      draftRevision: _requiredPositiveInt(json, 'draft_revision'),
      createdAt: DateTime.parse(_requiredString(json, 'created_at')).toUtc(),
      updatedAt: DateTime.parse(_requiredString(json, 'updated_at')).toUtc(),
    );
  }
}

class HostedAuthoringProject {
  const HostedAuthoringProject({
    required this.summary,
    required this.document,
  });

  final HostedAuthoringProjectSummary summary;
  final Map<String, Object?> document;

  factory HostedAuthoringProject.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> summaryJson = Map<String, Object?>.from(json)
      ..remove('document');
    final Object? rawDocument = json['document'];
    if (rawDocument is! Map<String, Object?>) {
      throw const FormatException(
        'Authoring project response has no document object.',
      );
    }
    return HostedAuthoringProject(
      summary: HostedAuthoringProjectSummary.fromJson(summaryJson),
      document: Map<String, Object?>.unmodifiable(rawDocument),
    );
  }
}

class HostedAuthoringProjectsApi {
  HostedAuthoringProjectsApi({required Uri baseUri, http.Client? client})
      : _baseUri = _validateBaseUri(baseUri),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final Uri _baseUri;
  final http.Client _client;
  final bool _ownsClient;

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<List<HostedAuthoringProjectSummary>> listProjects({
    required String accessToken,
    required String groupId,
    required String contentFormat,
  }) async {
    _validateToken(accessToken);
    _validateId(groupId, 'groupId');
    _validateContentFormat(contentFormat, 'contentFormat');
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'GET',
      path: '/hosted/authoring/groups/$groupId/projects',
      accessToken: accessToken,
      queryParameters: <String, String>{'content_format': contentFormat},
    );
    _requireExactFields(
      payload,
      const <String>{'projects'},
      'Authoring projects response',
    );
    final Object? rawProjects = payload['projects'];
    if (rawProjects is! List<Object?>) {
      throw const FormatException(
        'Authoring projects response has no projects list.',
      );
    }

    final List<HostedAuthoringProjectSummary> projects =
        <HostedAuthoringProjectSummary>[];
    final Set<String> contentIds = <String>{};
    for (final Object? rawProject in rawProjects) {
      if (rawProject is! Map<String, Object?>) {
        throw const FormatException(
          'Authoring projects response contains a non-object project.',
        );
      }
      final HostedAuthoringProjectSummary project =
          HostedAuthoringProjectSummary.fromJson(rawProject);
      if (project.groupId != groupId || project.contentFormat != contentFormat) {
        throw const FormatException(
          'Authoring projects response changed the requested scope.',
        );
      }
      if (!contentIds.add(project.contentId)) {
        throw const FormatException(
          'Authoring projects response contains a duplicate content_id.',
        );
      }
      projects.add(project);
    }
    return List<HostedAuthoringProjectSummary>.unmodifiable(projects);
  }

  Future<HostedAuthoringProject> loadProject({
    required String accessToken,
    required String contentId,
  }) async {
    _validateToken(accessToken);
    _validateId(contentId, 'contentId');
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'GET',
      path: '/hosted/authoring/projects/$contentId',
      accessToken: accessToken,
    );
    final HostedAuthoringProject project = HostedAuthoringProject.fromJson(payload);
    if (project.summary.contentId != contentId) {
      throw const FormatException(
        'Authoring project response changed the requested content scope.',
      );
    }
    return project;
  }

  Future<HostedAuthoringProjectSummary> createProject({
    required String accessToken,
    required String groupId,
    required String contentFormat,
    required Map<String, Object?> document,
  }) async {
    _validateToken(accessToken);
    _validateId(groupId, 'groupId');
    _validateContentFormat(contentFormat, 'contentFormat');
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'POST',
      path: '/hosted/authoring/projects',
      accessToken: accessToken,
      body: <String, Object?>{
        'group_id': groupId,
        'content_format': contentFormat,
        'document': document,
      },
    );
    final HostedAuthoringProjectSummary project =
        HostedAuthoringProjectSummary.fromJson(payload);
    if (project.groupId != groupId ||
        project.contentFormat != contentFormat ||
        project.draftRevision != 1) {
      throw const FormatException(
        'Created Authoring project returned unexpected scope or revision.',
      );
    }
    return project;
  }

  Future<void> deleteProject({
    required String accessToken,
    required String contentId,
  }) async {
    _validateToken(accessToken);
    _validateId(contentId, 'contentId');
    final Uri uri = _baseUri.resolve('/hosted/authoring/projects/$contentId');
    final http.Response response = await _client.delete(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    );
    if (response.statusCode == 204) return;
    _decodeJsonResponse(response);
    throw StateError('Expected HTTP 204 for ${uri.path}.');
  }

  Future<Map<String, Object?>> _jsonRequest({
    required String method,
    required String path,
    required String accessToken,
    Map<String, String>? queryParameters,
    Map<String, Object?>? body,
  }) async {
    Uri uri = _baseUri.resolve(path);
    if (queryParameters != null) {
      uri = uri.replace(queryParameters: queryParameters);
    }
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $accessToken',
    };
    if (body != null) headers['Content-Type'] = 'application/json';

    final http.Response response;
    if (method == 'GET') {
      if (body != null) throw ArgumentError('GET request must not contain a body.');
      response = await _client.get(uri, headers: headers);
    } else if (method == 'POST') {
      if (queryParameters != null) {
        throw ArgumentError('POST request must not contain query parameters.');
      }
      response = await _client.post(
        uri,
        headers: headers,
        body: body == null ? null : jsonEncode(body),
      );
    } else {
      throw ArgumentError.value(method, 'method', 'unsupported HTTP method');
    }
    return _decodeJsonResponse(response);
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

void _validateToken(String accessToken) {
  if (accessToken.isEmpty) {
    throw ArgumentError.value(accessToken, 'accessToken', 'must not be empty');
  }
}

void _validateId(String value, String label) {
  if (!_authoringProjectIdPattern.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      label,
      'must be a 32-character lowercase hexadecimal ID',
    );
  }
}

void _validateContentFormat(String value, String label) {
  if (!_authoringContentFormatPattern.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      label,
      'must be a namespaced versioned content format',
    );
  }
}

String _requiredId(Map<String, Object?> json, String key) {
  final String value = _requiredString(json, key);
  if (!_authoringProjectIdPattern.hasMatch(value)) {
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
