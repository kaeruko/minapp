import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/api.dart';
import 'package:minapp_mobile/hosted_authoring_projects_api.dart';

const String _groupId = '22222222222222222222222222222222';
const String _contentId = '33333333333333333333333333333333';
const String _otherContentId = '44444444444444444444444444444444';
const String _format = 'example/quiz@1';

http.Response _json(int status, Map<String, Object?> body) => http.Response(
      jsonEncode(body),
      status,
      headers: const <String, String>{'content-type': 'application/json'},
    );

Map<String, Object?> _summary({
  required String contentId,
  required String format,
  int revision = 1,
}) =>
    <String, Object?>{
      'content_id': contentId,
      'group_id': _groupId,
      'content_format': format,
      'status': 'draft',
      'draft_revision': revision,
      'assets': <Object?>[],
      'created_at': '2026-09-07T03:00:00Z',
      'updated_at': '2026-09-07T03:00:00Z',
    };

void main() {
  test('list scopes projects by arbitrary content_format', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(
        request.url.path,
        '/hosted/authoring/groups/$_groupId/projects',
      );
      expect(request.url.queryParameters, const <String, String>{
        'content_format': _format,
      });
      expect(request.headers['authorization'], 'Bearer owner-token');
      return _json(200, <String, Object?>{
        'projects': <Object?>[
          _summary(contentId: _contentId, format: _format),
        ],
      });
    });
    final HostedAuthoringProjectsApi api = HostedAuthoringProjectsApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    final List<HostedAuthoringProjectSummary> projects = await api.listProjects(
      accessToken: 'owner-token',
      groupId: _groupId,
      contentFormat: _format,
    );

    expect(projects, hasLength(1));
    expect(projects.single.contentId, _contentId);
    expect(projects.single.contentFormat, _format);
  });

  test('list rejects a server response outside requested scope', () async {
    final MockClient client = MockClient((http.Request request) async {
      return _json(200, <String, Object?>{
        'projects': <Object?>[
          _summary(contentId: _otherContentId, format: 'example/other@1'),
        ],
      });
    });
    final HostedAuthoringProjectsApi api = HostedAuthoringProjectsApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    await expectLater(
      api.listProjects(
        accessToken: 'owner-token',
        groupId: _groupId,
        contentFormat: _format,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('create can send an empty opaque document for Editor initialization', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/hosted/authoring/projects');
      final Object? decoded = jsonDecode(request.body);
      expect(decoded, isA<Map<String, Object?>>());
      final Map<String, Object?> body = decoded! as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{'group_id', 'content_format', 'document'});
      expect(body['group_id'], _groupId);
      expect(body['content_format'], _format);
      expect(body['document'], <String, Object?>{});
      return _json(201, _summary(contentId: _contentId, format: _format));
    });
    final HostedAuthoringProjectsApi api = HostedAuthoringProjectsApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    final HostedAuthoringProjectSummary created = await api.createProject(
      accessToken: 'owner-token',
      groupId: _groupId,
      contentFormat: _format,
      document: const <String, Object?>{},
    );

    expect(created.contentId, _contentId);
    expect(created.draftRevision, 1);
  });

  test('load keeps document opaque and rejects content id scope changes', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.url.path, '/hosted/authoring/projects/$_contentId');
      return _json(200, <String, Object?>{
        ..._summary(contentId: _contentId, format: _format, revision: 2),
        'document': <String, Object?>{
          'anything': <Object?>['the', 'host', 'does', 'not', 'interpret'],
        },
      });
    });
    final HostedAuthoringProjectsApi api = HostedAuthoringProjectsApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    final HostedAuthoringProject project = await api.loadProject(
      accessToken: 'owner-token',
      contentId: _contentId,
    );
    expect(project.summary.contentFormat, _format);
    expect(project.document['anything'], isA<List<Object?>>());
  });

  test('load rejects a response that changes requested content id', () async {
    final MockClient client = MockClient((http.Request request) async {
      return _json(200, <String, Object?>{
        ..._summary(contentId: _otherContentId, format: _format),
        'document': <String, Object?>{},
      });
    });
    final HostedAuthoringProjectsApi api = HostedAuthoringProjectsApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    await expectLater(
      api.loadProject(accessToken: 'owner-token', contentId: _contentId),
      throwsA(isA<FormatException>()),
    );
  });

  test('delete sends only authenticated content scope and accepts 204', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'DELETE');
      expect(request.url.path, '/hosted/authoring/projects/$_contentId');
      expect(request.url.query, isEmpty);
      expect(request.headers['authorization'], 'Bearer owner-token');
      expect(request.body, isEmpty);
      return http.Response('', 204);
    });
    final HostedAuthoringProjectsApi api = HostedAuthoringProjectsApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    await api.deleteProject(
      accessToken: 'owner-token',
      contentId: _contentId,
    );
  });

  test('delete preserves backend error instead of treating it as success', () async {
    final MockClient client = MockClient((http.Request request) async {
      return _json(409, <String, Object?>{
        'error': 'content_not_editable',
        'message': 'Authoring content is not in a deletable state.',
      });
    });
    final HostedAuthoringProjectsApi api = HostedAuthoringProjectsApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    await expectLater(
      api.deleteProject(
        accessToken: 'owner-token',
        contentId: _contentId,
      ),
      throwsA(
        isA<ApiException>()
            .having((ApiException error) => error.statusCode, 'statusCode', 409)
            .having(
              (ApiException error) => error.code,
              'code',
              'content_not_editable',
            ),
      ),
    );
  });
}
