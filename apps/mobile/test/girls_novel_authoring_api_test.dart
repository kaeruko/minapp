import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/girls_novel_authoring_api.dart';

const String _groupId = '22222222222222222222222222222222';
const String _contentId = '33333333333333333333333333333333';
const String _otherContentId = '44444444444444444444444444444444';

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
      'created_at': '2026-09-06T09:00:00Z',
      'updated_at': '2026-09-06T10:00:00Z',
    };

Map<String, Object?> _novelDocument({int revision = 1, String title = '放課後'}) =>
    <String, Object?>{
      'content_format': minappNovelContentFormat,
      'schema_version': 1,
      'content_revision': revision,
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
              'type': 'end',
              'label': 'END',
            },
          ],
        },
      },
    };

void main() {
  test('list filters explicit non-Novel formats without changing group scope', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(
        request.url.path,
        '/hosted/authoring/groups/$_groupId/projects',
      );
      expect(request.headers['authorization'], 'Bearer owner-token');
      return _json(200, <String, Object?>{
        'projects': <Object?>[
          _summary(
            contentId: _contentId,
            format: minappNovelContentFormat,
          ),
          _summary(
            contentId: _otherContentId,
            format: 'example/quiz@1',
          ),
        ],
      });
    });
    final GirlsNovelAuthoringApi api = GirlsNovelAuthoringApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    final List<GirlsNovelProjectSummary> projects = await api.listProjects(
      accessToken: 'owner-token',
      groupId: _groupId,
    );

    expect(projects, hasLength(1));
    expect(projects.single.contentId, _contentId);
    expect(projects.single.contentFormat, minappNovelContentFormat);
  });

  test('create sends canonical minimal minapp/novel@1 Master Data', () async {
    final List<http.Request> requests = <http.Request>[];
    final MockClient client = MockClient((http.Request request) async {
      requests.add(request);
      expect(request.method, 'POST');
      expect(request.url.path, '/hosted/authoring/projects');
      expect(request.headers['authorization'], 'Bearer owner-token');
      final Object? decoded = jsonDecode(request.body);
      expect(decoded, isA<Map<String, Object?>>());
      final Map<String, Object?> body = decoded! as Map<String, Object?>;
      expect(body.keys.toSet(), <String>{'group_id', 'content_format', 'document'});
      expect(body['group_id'], _groupId);
      expect(body['content_format'], minappNovelContentFormat);
      final Map<String, Object?> document = body['document']! as Map<String, Object?>;
      expect(
        document.keys.toSet(),
        <String>{
          'content_format',
          'schema_version',
          'content_revision',
          'title',
          'start_scene',
          'assets',
          'characters',
          'scenes',
        },
      );
      expect(document['content_format'], minappNovelContentFormat);
      expect(document['schema_version'], 1);
      expect(document['content_revision'], 1);
      expect(document['title'], 'はじめての物語');
      expect(document['start_scene'], 'scene_001');
      final Map<String, Object?> scenes = document['scenes']! as Map<String, Object?>;
      final Map<String, Object?> scene = scenes['scene_001']! as Map<String, Object?>;
      final List<Object?> events = scene['events']! as List<Object?>;
      expect((events.first as Map<String, Object?>)['type'], 'dialogue');
      expect((events.last as Map<String, Object?>)['type'], 'end');
      return _json(
        201,
        _summary(
          contentId: _contentId,
          format: minappNovelContentFormat,
        ),
      );
    });
    final GirlsNovelAuthoringApi api = GirlsNovelAuthoringApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    final GirlsNovelProjectSummary created = await api.createProject(
      accessToken: 'owner-token',
      groupId: _groupId,
      title: 'はじめての物語',
    );

    expect(created.contentId, _contentId);
    expect(created.draftRevision, 1);
    expect(requests, hasLength(1));
  });

  test('load rejects a response that changes requested content scope', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.url.path, '/hosted/authoring/projects/$_contentId');
      return _json(200, <String, Object?>{
        ..._summary(
          contentId: _otherContentId,
          format: minappNovelContentFormat,
        ),
        'document': _novelDocument(),
      });
    });
    final GirlsNovelAuthoringApi api = GirlsNovelAuthoringApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    await expectLater(
      api.loadProject(
        accessToken: 'owner-token',
        contentId: _contentId,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('load exposes title only after strict Novel envelope validation', () async {
    final MockClient client = MockClient((http.Request request) async => _json(
          200,
          <String, Object?>{
            ..._summary(
              contentId: _contentId,
              format: minappNovelContentFormat,
              revision: 3,
            ),
            'document': _novelDocument(revision: 2, title: '放課後の秘密'),
          },
        ));
    final GirlsNovelAuthoringApi api = GirlsNovelAuthoringApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    final GirlsNovelProject project = await api.loadProject(
      accessToken: 'owner-token',
      contentId: _contentId,
    );

    expect(project.title, '放課後の秘密');
    expect(project.summary.draftRevision, 3);
  });
}
