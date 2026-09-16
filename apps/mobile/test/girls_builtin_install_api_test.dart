import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/api.dart';
import 'package:minapp_mobile/girls/girls_builtin_install_api.dart';
import 'package:minapp_mobile/girls/hosted_girls_api.dart';

const String _groupId = '22222222222222222222222222222222';
const String _appId = '44444444444444444444444444444444';
const String _ownerUserId = '55555555555555555555555555555555';
const String _contentId = '66666666666666666666666666666666';
const String _novelContentFormat = 'minapp/novel@1';
const String _novelSampleTitle = 'ひみつの放課後';

http.Response _json(int status, Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  status,
  headers: const <String, String>{'content-type': 'application/json'},
);

Map<String, Object?> _installedApp({
  String groupId = _groupId,
  String builtinId = novelEditorBuiltinId,
}) {
  final bool isEditor = builtinId == novelEditorBuiltinId;
  return <String, Object?>{
    'app_id': _appId,
    'group_id': groupId,
    'title': isEditor ? 'ノベルゲームメーカー' : 'ひみつの放課後',
    'source_kind': 'builtin',
    'created_at': '2026-09-07T01:00:00Z',
    'owner_user_id': _ownerUserId,
    'builtin_id': builtinId,
    'builtin_asset_path': isEditor
        ? 'assets/builtin/novel_editor/index.html'
        : 'assets/builtin/novel_starter/index.html',
    'builtin_version': isEditor ? 1 : 4,
    'editable': false,
  };
}

Map<String, Object?> _projectSummary({String contentId = _contentId}) {
  return <String, Object?>{
    'content_id': contentId,
    'group_id': _groupId,
    'content_format': _novelContentFormat,
    'status': 'draft',
    'draft_revision': 1,
    'assets': <Object?>[],
    'created_at': '2026-09-16T01:00:00Z',
    'updated_at': '2026-09-16T01:00:00Z',
  };
}

Map<String, Object?> _sampleProject() {
  return <String, Object?>{
    ..._projectSummary(),
    'document': <String, Object?>{'title': _novelSampleTitle},
  };
}

bool _isHydrateRequest(http.Request request) =>
    request.method == 'POST' &&
    request.url.path == '/hosted/authoring/projects/$_contentId/samples/novel';

void main() {
  test('Novel Editor setup installs missing Player first, then Editor and sample', () async {
    final List<http.Request> captured = <http.Request>[];
    final MockClient client = MockClient((http.Request request) async {
      captured.add(request);
      if (request.method == 'GET' &&
          request.url.path == '/hosted/groups/$_groupId/apps') {
        return _json(200, const <String, Object?>{'apps': <Object?>[]});
      }
      if (request.method == 'GET' &&
          request.url.path == '/hosted/authoring/groups/$_groupId/projects') {
        expect(request.url.queryParameters['content_format'], _novelContentFormat);
        return _json(200, const <String, Object?>{'projects': <Object?>[]});
      }
      if (request.method == 'POST' &&
          request.url.path == '/hosted/groups/$_groupId/apps/install') {
        final Map<String, Object?> body =
            jsonDecode(request.body) as Map<String, Object?>;
        final String builtinId = body['builtin_id']! as String;
        return _json(201, _installedApp(builtinId: builtinId));
      }
      if (request.method == 'POST' &&
          request.url.path == '/hosted/authoring/projects') {
        final Map<String, Object?> body =
            jsonDecode(request.body) as Map<String, Object?>;
        expect(body['group_id'], _groupId);
        expect(body['content_format'], _novelContentFormat);
        final Map<String, Object?> document =
            body['document']! as Map<String, Object?>;
        expect(document['title'], _novelSampleTitle);
        return _json(201, _projectSummary());
      }
      if (_isHydrateRequest(request)) {
        expect(request.body, isEmpty);
        return _json(200, _projectSummary());
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    final GirlsBuiltinInstallApi api = GirlsBuiltinInstallApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    final HostedGroupApp app = await api.installNovelEditor(
      accessToken: 'owner-token',
      groupId: _groupId,
    );

    expect(captured, hasLength(6));
    expect(captured[0].method, 'GET');
    expect(captured[0].url.path, '/hosted/groups/$_groupId/apps');
    expect(captured[0].headers['authorization'], 'Bearer owner-token');
    expect(jsonDecode(captured[1].body), const <String, Object?>{
      'builtin_id': novelPlayerBuiltinId,
    });
    expect(jsonDecode(captured[2].body), const <String, Object?>{
      'builtin_id': novelEditorBuiltinId,
    });
    expect(captured[3].url.path, '/hosted/authoring/groups/$_groupId/projects');
    expect(captured[4].url.path, '/hosted/authoring/projects');
    expect(captured[5].url.path, '/hosted/authoring/projects/$_contentId/samples/novel');
    expect(app.appId, _appId);
    expect(app.groupId, _groupId);
    expect(app.sourceKind, 'builtin');
    expect(app.builtinId, novelEditorBuiltinId);
  });

  test('Novel Editor setup reuses an already-installed Player and seeds sample', () async {
    final List<http.Request> captured = <http.Request>[];
    final MockClient client = MockClient((http.Request request) async {
      captured.add(request);
      if (request.method == 'GET' &&
          request.url.path == '/hosted/groups/$_groupId/apps') {
        return _json(200, <String, Object?>{
          'apps': <Object?>[
            _installedApp(builtinId: novelPlayerBuiltinId),
          ],
        });
      }
      if (request.method == 'GET' &&
          request.url.path == '/hosted/authoring/groups/$_groupId/projects') {
        return _json(200, const <String, Object?>{'projects': <Object?>[]});
      }
      if (request.method == 'POST' &&
          request.url.path == '/hosted/groups/$_groupId/apps/install') {
        return _json(201, _installedApp());
      }
      if (request.method == 'POST' &&
          request.url.path == '/hosted/authoring/projects') {
        return _json(201, _projectSummary());
      }
      if (_isHydrateRequest(request)) {
        return _json(200, _projectSummary());
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    final GirlsBuiltinInstallApi api = GirlsBuiltinInstallApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    final HostedGroupApp app = await api.installNovelEditor(
      accessToken: 'owner-token',
      groupId: _groupId,
    );

    expect(captured, hasLength(5));
    expect(captured[0].method, 'GET');
    expect(captured[1].url.path, '/hosted/groups/$_groupId/apps/install');
    expect(jsonDecode(captured[1].body), const <String, Object?>{
      'builtin_id': novelEditorBuiltinId,
    });
    expect(captured[2].url.path, '/hosted/authoring/groups/$_groupId/projects');
    expect(captured[3].url.path, '/hosted/authoring/projects');
    expect(captured[4].url.path, '/hosted/authoring/projects/$_contentId/samples/novel');
    expect(app.builtinId, novelEditorBuiltinId);
  });

  test('ensureNovelEditor reuses installed Editor, Player, and existing sample', () async {
    final List<http.Request> captured = <http.Request>[];
    var groupAppsGetCount = 0;
    final MockClient client = MockClient((http.Request request) async {
      captured.add(request);
      if (request.method == 'GET' &&
          request.url.path == '/hosted/groups/$_groupId/apps') {
        groupAppsGetCount += 1;
        if (groupAppsGetCount == 1) {
          return _json(200, <String, Object?>{
            'apps': <Object?>[
              _installedApp(builtinId: novelPlayerBuiltinId),
            ],
          });
        }
        return _json(200, <String, Object?>{
          'apps': <Object?>[
            _installedApp(builtinId: novelPlayerBuiltinId),
            _installedApp(),
          ],
        });
      }
      if (request.method == 'GET' &&
          request.url.path == '/hosted/authoring/groups/$_groupId/projects') {
        return _json(200, <String, Object?>{
          'projects': <Object?>[_projectSummary()],
        });
      }
      if (request.method == 'GET' &&
          request.url.path == '/hosted/authoring/projects/$_contentId') {
        return _json(200, _sampleProject());
      }
      if (_isHydrateRequest(request)) {
        return _json(200, _projectSummary());
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    final GirlsBuiltinInstallApi api = GirlsBuiltinInstallApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    final HostedGroupApp app = await api.ensureNovelEditor(
      accessToken: 'owner-token',
      groupId: _groupId,
    );

    expect(captured, hasLength(5));
    expect(captured.take(4).every((http.Request request) => request.method == 'GET'), isTrue);
    expect(captured.last.url.path, '/hosted/authoring/projects/$_contentId/samples/novel');
    expect(app.builtinId, novelEditorBuiltinId);
  });

  test('ensureNovelPlayer repairs a group that is missing the Player', () async {
    final List<http.Request> captured = <http.Request>[];
    final MockClient client = MockClient((http.Request request) async {
      captured.add(request);
      if (request.method == 'GET') {
        return _json(200, <String, Object?>{
          'apps': <Object?>[_installedApp()],
        });
      }
      return _json(
        201,
        _installedApp(builtinId: novelPlayerBuiltinId),
      );
    });
    final GirlsBuiltinInstallApi api = GirlsBuiltinInstallApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    final HostedGroupApp app = await api.ensureNovelPlayer(
      accessToken: 'owner-token',
      groupId: _groupId,
    );

    expect(captured, hasLength(2));
    expect(captured[0].method, 'GET');
    expect(captured[1].method, 'POST');
    expect(jsonDecode(captured[1].body), const <String, Object?>{
      'builtin_id': novelPlayerBuiltinId,
    });
    expect(app.builtinId, novelPlayerBuiltinId);
  });

  test('group app list cannot silently change group scope', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      return _json(200, <String, Object?>{
        'apps': <Object?>[
          _installedApp(
            groupId: '3' * 32,
            builtinId: novelPlayerBuiltinId,
          ),
        ],
      });
    });
    final GirlsBuiltinInstallApi api = GirlsBuiltinInstallApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    await expectLater(
      api.ensureNovelPlayer(accessToken: 'owner-token', groupId: _groupId),
      throwsA(isA<FormatException>()),
    );
  });

  test('Player install response cannot silently change builtin id', () async {
    final MockClient client = MockClient((http.Request request) async {
      if (request.method == 'GET') {
        return _json(200, const <String, Object?>{'apps': <Object?>[]});
      }
      return _json(201, _installedApp());
    });
    final GirlsBuiltinInstallApi api = GirlsBuiltinInstallApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    await expectLater(
      api.ensureNovelPlayer(accessToken: 'owner-token', groupId: _groupId),
      throwsA(isA<FormatException>()),
    );
  });

  test('Player setup failure stops before Editor installation', () async {
    final List<http.Request> captured = <http.Request>[];
    final MockClient client = MockClient((http.Request request) async {
      captured.add(request);
      if (request.method == 'GET') {
        return _json(200, const <String, Object?>{'apps': <Object?>[]});
      }
      return _json(500, const <String, Object?>{
        'error': 'player_setup_failed',
        'message': 'Player setup failed.',
      });
    });
    final GirlsBuiltinInstallApi api = GirlsBuiltinInstallApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    await expectLater(
      api.installNovelEditor(accessToken: 'owner-token', groupId: _groupId),
      throwsA(
        isA<ApiException>()
            .having(
              (ApiException error) => error.statusCode,
              'statusCode',
              500,
            )
            .having(
              (ApiException error) => error.code,
              'code',
              'player_setup_failed',
            ),
      ),
    );
    expect(captured, hasLength(2));
    expect(captured[0].method, 'GET');
    expect(captured[1].method, 'POST');
    expect(jsonDecode(captured[1].body), const <String, Object?>{
      'builtin_id': novelPlayerBuiltinId,
    });
  });
}
