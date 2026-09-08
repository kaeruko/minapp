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

void main() {
  test('Novel Editor setup installs missing Player first, then Editor', () async {
    final List<http.Request> captured = <http.Request>[];
    final MockClient client = MockClient((http.Request request) async {
      captured.add(request);
      if (request.method == 'GET') {
        return _json(200, const <String, Object?>{'apps': <Object?>[]});
      }
      final Map<String, Object?> body =
          jsonDecode(request.body) as Map<String, Object?>;
      final String builtinId = body['builtin_id']! as String;
      return _json(201, _installedApp(builtinId: builtinId));
    });
    final GirlsBuiltinInstallApi api = GirlsBuiltinInstallApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    final HostedGroupApp app = await api.installNovelEditor(
      accessToken: 'owner-token',
      groupId: _groupId,
    );

    expect(captured, hasLength(3));
    expect(captured[0].method, 'GET');
    expect(captured[0].url.path, '/hosted/groups/$_groupId/apps');
    expect(captured[0].headers['authorization'], 'Bearer owner-token');
    expect(jsonDecode(captured[1].body), const <String, Object?>{
      'builtin_id': novelPlayerBuiltinId,
    });
    expect(jsonDecode(captured[2].body), const <String, Object?>{
      'builtin_id': novelEditorBuiltinId,
    });
    expect(app.appId, _appId);
    expect(app.groupId, _groupId);
    expect(app.sourceKind, 'builtin');
    expect(app.builtinId, novelEditorBuiltinId);
  });

  test('Novel Editor setup reuses an already-installed Player', () async {
    final List<http.Request> captured = <http.Request>[];
    final MockClient client = MockClient((http.Request request) async {
      captured.add(request);
      if (request.method == 'GET') {
        return _json(200, <String, Object?>{
          'apps': <Object?>[
            _installedApp(builtinId: novelPlayerBuiltinId),
          ],
        });
      }
      return _json(201, _installedApp());
    });
    final GirlsBuiltinInstallApi api = GirlsBuiltinInstallApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    final HostedGroupApp app = await api.installNovelEditor(
      accessToken: 'owner-token',
      groupId: _groupId,
    );

    expect(captured, hasLength(2));
    expect(captured[0].method, 'GET');
    expect(captured[1].method, 'POST');
    expect(jsonDecode(captured[1].body), const <String, Object?>{
      'builtin_id': novelEditorBuiltinId,
    });
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
