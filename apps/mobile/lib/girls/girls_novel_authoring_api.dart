import 'package:http/http.dart' as http;

import 'girls_authoring_projects_api.dart';

const String minappNovelContentFormat = 'minapp/novel@1';

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
    return GirlsNovelProjectSummary.fromGeneric(
      GirlsAuthoringProjectSummary.fromJson(json),
    );
  }

  factory GirlsNovelProjectSummary.fromGeneric(
    GirlsAuthoringProjectSummary summary,
  ) {
    if (summary.contentFormat != minappNovelContentFormat) {
      throw FormatException(
        'Novel Authoring response returned unsupported format '
        '${summary.contentFormat}.',
      );
    }
    return GirlsNovelProjectSummary(
      contentId: summary.contentId,
      groupId: summary.groupId,
      contentFormat: summary.contentFormat,
      status: summary.status,
      draftRevision: summary.draftRevision,
      createdAt: summary.createdAt,
      updatedAt: summary.updatedAt,
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
    return GirlsNovelProject.fromGeneric(
      GirlsAuthoringProject.fromJson(json),
    );
  }

  factory GirlsNovelProject.fromGeneric(GirlsAuthoringProject project) {
    final GirlsNovelProjectSummary summary =
        GirlsNovelProjectSummary.fromGeneric(project.summary);
    _validateNovelDocumentEnvelope(project.document, summary.draftRevision);
    return GirlsNovelProject(
      summary: summary,
      document: project.document,
    );
  }
}

class GirlsNovelAuthoringApi {
  GirlsNovelAuthoringApi({required Uri baseUri, http.Client? client})
      : _projectsApi = GirlsAuthoringProjectsApi(
          baseUri: baseUri,
          client: client,
        );

  final GirlsAuthoringProjectsApi _projectsApi;

  void close() => _projectsApi.close();

  Future<List<GirlsNovelProjectSummary>> listProjects({
    required String accessToken,
    required String groupId,
  }) async {
    final List<GirlsAuthoringProjectSummary> projects =
        await _projectsApi.listProjects(
      accessToken: accessToken,
      groupId: groupId,
      contentFormat: minappNovelContentFormat,
    );
    return List<GirlsNovelProjectSummary>.unmodifiable(
      projects.map(GirlsNovelProjectSummary.fromGeneric),
    );
  }

  Future<GirlsNovelProject> loadProject({
    required String accessToken,
    required String contentId,
  }) async {
    final GirlsAuthoringProject project = await _projectsApi.loadProject(
      accessToken: accessToken,
      contentId: contentId,
    );
    return GirlsNovelProject.fromGeneric(project);
  }

  Future<GirlsNovelProjectSummary> createProject({
    required String accessToken,
    required String groupId,
    String title = '新しいノベル',
  }) async {
    if (title.isEmpty || title.length > 100 || title.trim() != title) {
      throw ArgumentError.value(
        title,
        'title',
        'must be 1-100 trimmed characters',
      );
    }
    final GirlsAuthoringProjectSummary project =
        await _projectsApi.createProject(
      accessToken: accessToken,
      groupId: groupId,
      contentFormat: minappNovelContentFormat,
      document: _newNovelDocument(title),
    );
    return GirlsNovelProjectSummary.fromGeneric(project);
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
    throw const FormatException(
      'Novel Master Data has an unsupported format/schema.',
    );
  }
  final Object? contentRevision = document['content_revision'];
  if (contentRevision is! int || contentRevision < 1) {
    throw const FormatException(
      'Novel Master Data has an invalid content_revision.',
    );
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
    throw const FormatException(
      'Novel Master Data collections must be objects.',
    );
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('JSON field $key must be a non-empty string.');
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
