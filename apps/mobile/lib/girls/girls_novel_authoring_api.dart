import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';

const String minappNovelContentFormat = 'minapp/novel@1';

final RegExp _novelAuthoringIdPattern = RegExp(r'^[0-9a-f]{32}$');

class GirlsNovelProjectSummary {
  const GirlsNovelProjectSummary({
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

  factory GirlsNovelProjectSummary.fromJson(Map<String, Object?> json) {
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
    if (contentFormat != minappNovelContentFormat) {
      throw FormatException(
        'Novel Authoring response returned unsupported format $contentFormat.',
      );
    }
    final String status = _requiredString(json, 'status');
    if (status != 'draft') {
      throw FormatException(
        'Novel Authoring response returned unsupported status $status.',
      );
    }
    final Object? assets = json['assets'];
    if (assets is! List<Object?>) {
      throw const FormatException('Authoring project assets must be a list.');
    }
    return GirlsNovelProjectSummary(
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

class GirlsNovelProject {
  const GirlsNovelProject({
    required this.summary,
    required this.document,
  });

  final GirlsNovelProjectSummary summary;
  final Map<String, Object?> document;

  String get title {
    final Object? value = document['title'];
    if (value is! String || value.isEmpty || value.length > 100) {
      throw const FormatException('Novel Master Data has an invalid title.');
    }
    return value;
  }

  factory GirlsNovelProject.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> summaryJson = Map<String, Object?>.from(json)
      ..remove('document');
    final Object? rawDocument = json['document'];
    if (rawDocument is! Map<String, Object?>) {
      throw const FormatException('Authoring project response has no document object.');
    }
    final GirlsNovelProjectSummary summary =
        GirlsNovelProjectSummary.fromJson(summaryJson);
    _validateNovelDocumentEnvelope(rawDocument, summary.draftRevision);
    return GirlsNovelProject(
      summary: summary,
      document: Map<String, Object?>.unmodifiable(rawDocument),
    );
  }
}

class GirlsNovelAuthoringApi {
  GirlsNovelAuthoringApi({required Uri baseUri, http.Client? client})
      : _baseUri = _validateBaseUri(baseUri),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final Uri _baseUri;
  final http.Client _client;
  final bool _ownsClient;

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<List<GirlsNovelProjectSummary>> listProjects({
    required String accessToken,
    required String groupId,
  }) async {
    _validateToken(accessToken);
    _validateId(groupId, 'groupId');
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'GET',
      path: '/hosted/authoring/groups/$groupId/projects',
      accessToken: accessToken,
    );
    _requireExactFields(
      payload,
      const <String>{'projects'},
      'Authoring projects response',
    );
    final Object? rawProjects = payload['projects'];
    if (rawProjects is! List<Object?>) {
      throw const FormatException('Authoring projects response has no projects list.');
    }

    final List<GirlsNovelProjectSummary> projects =
        <GirlsNovelProjectSummary>[];
    for (final Object? rawProject in rawProjects) {
      if (rawProject is! Map<String, Object?>) {
        throw const FormatException(
          'Authoring projects response contains a non-object project.',
        );
      }
      final Object? rawFormat = rawProject['content_format'];
      if (rawFormat is! String || rawFormat.isEmpty) {
        throw const FormatException(
          'Authoring project summary has an invalid content_format.',
        );
      }
      if (rawFormat != minappNovelContentFormat) {
        continue;
      }
      final GirlsNovelProjectSummary project =
          GirlsNovelProjectSummary.fromJson(rawProject);
      if (project.groupId != groupId) {
        throw const FormatException(
          'Authoring projects response changed the requested group scope.',
        );
      }
      projects.add(project);
    }
    return List<GirlsNovelProjectSummary>.unmodifiable(projects);
  }

  Future<GirlsNovelProject> loadProject({
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
    final GirlsNovelProject project = GirlsNovelProject.fromJson(payload);
    if (project.summary.contentId != contentId) {
      throw const FormatException(
        'Authoring project response changed the requested content scope.',
      );
    }
    return project;
  }

  Future<GirlsNovelProjectSummary> createProject({
    required String accessToken,
    required String groupId,
    String title = '新しいノベル',
  }) async {
    _validateToken(accessToken);
    _validateId(groupId, 'groupId');
    if (title.isEmpty || title.length > 100 || title.trim() != title) {
      throw ArgumentError.value(title, 'title', 'must be 1-100 trimmed characters');
    }
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'POST',
      path: '/hosted/authoring/projects',
      accessToken: accessToken,
      body: <String, Object?>{
        'group_id': groupId,
        'content_format': minappNovelContentFormat,
        'document': _newNovelDocument(title),
      },
    );
    final GirlsNovelProjectSummary project =
        GirlsNovelProjectSummary.fromJson(payload);
    if (project.groupId != groupId || project.draftRevision != 1) {
      throw const FormatException(
        'Created Authoring project returned unexpected scope or revision.',
      );
    }
    return project;
  }

  Future<Map<String, Object?>> _jsonRequest({
    required String method,
    required String path,
    required String accessToken,
    Map<String, Object?>? body,
  }) async {
    final Uri uri = _baseUri.resolve(path);
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
      if (error is! String || error.isEmpty || message is! String || message.isEmpty) {
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

Map<String, Object?> _newNovelDocument(String title) => <String, Object?>{
      'content_format': minappNovelContentFormat,
      'schema_version': 1,
      'content_revision': 1,
      'title': title,
      'start_scene': 'scene_001',
      'assets': <String, Object?>{},
      'characters': <String, Object?>{},
      'scenes': <String, Object?>{
        'scene_001': <String, Object?>{
          'id': 'scene_001',
          'events': <Object?>[
            <String, Object?>{
              'id': 'event_001',
              'type': 'dialogue',
              'text': 'ここから物語をはじめよう。',
            },
            <String, Object?>{
              'id': 'event_002',
              'type': 'end',
              'label': 'END',
            },
          ],
        },
      },
    };

void _validateNovelDocumentEnvelope(
  Map<String, Object?> document,
  int draftRevision,
) {
  final Set<String> expected = <String>{
    'content_format',
    'schema_version',
    'content_revision',
    'title',
    'start_scene',
    'assets',
    'characters',
    'scenes',
  };
  _requireExactFields(document, expected, 'Novel Master Data');
  if (document['content_format'] != minappNovelContentFormat ||
      document['schema_version'] != 1) {
    throw const FormatException('Novel Master Data has an unsupported format/schema.');
  }
  final Object? contentRevision = document['content_revision'];
  if (contentRevision is! int || contentRevision < 1) {
    throw const FormatException('Novel Master Data has an invalid content_revision.');
  }
  if (draftRevision < contentRevision) {
    throw const FormatException(
      'Novel content_revision cannot exceed the Authoring draft revision.',
    );
  }
  _requiredString(document, 'title');
  _requiredString(document, 'start_scene');
  if (document['assets'] is! Map<String, Object?> ||
      document['characters'] is! Map<String, Object?> ||
      document['scenes'] is! Map<String, Object?>) {
    throw const FormatException('Novel Master Data collections must be objects.');
  }
}

void _validateToken(String accessToken) {
  if (accessToken.isEmpty) {
    throw ArgumentError.value(accessToken, 'accessToken', 'must not be empty');
  }
}

void _validateId(String value, String label) {
  if (!_novelAuthoringIdPattern.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      label,
      'must be a 32-character lowercase hexadecimal ID',
    );
  }
}

String _requiredId(Map<String, Object?> json, String key) {
  final String value = _requiredString(json, key);
  if (!_novelAuthoringIdPattern.hasMatch(value)) {
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
