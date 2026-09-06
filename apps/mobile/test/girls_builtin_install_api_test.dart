import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/api.dart';
import 'package:minapp_mobile/girls/girls_builtin_install_api.dart';
import 'package:minapp_mobile/girls/hosted_girls_api.dart';

const String _groupId = '22222222222222222222222222222222';
const String _appId = '44444444444444444444444444444444';

http.Response _json(int status, Map<String, Object?> body) => http.Response(
      jsonEncode(body),
      status,
      headers: const <String, String>{'content-type': 'application/json'},
    );

Map<String, Object?> _installedApp({String groupId = _groupId}) =>
    <String, Object?>{
      'app_id': _appId,
      'group_id': groupId,
      'title': 'ノベルゲームメーカー',
      'source_kind': 'builtin',
      'created_at': '2026-09-07T01:00:00Z',
      'builtin_id': novelEditorBuiltinId,
      'builtin_asset_path': 'assets/builtin/novel_editor/index.html',
      'builtin_version': 1,
      'editable': false,
    };

void main() {
  test('Novel Editor install uses JWT and exact builtin id', () async {
    late http.Request captured;
    final MockClient client = MockClient((http.Request request) async {
      captured = request;
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

    expect(captured.method, 'POST');
    expect(
      captured.url.path,
      '/hosted/groups/$_groupId/apps/install',
    );
    expect(captured.headers['authorization'], 'Bearer owner-token');
    expect(
      jsonDecode(captured.body),
      const <String, Object?>{'builtin_id': novelEditorBuiltinId},
    );
    expect(app.appId, _appId);
    expect(app.groupId, _groupId);
    expect(app.sourceKind, 'builtin');
    expect(app.builtinId, novelEditorBuiltinId);
  });

  test('install response cannot silently change group scope', () async {
    final MockClient client = MockClient(
      (http.Request request) async => _json(
        201,
        _installedApp(groupId: '3' * 32),
      ),
    );
    final GirlsBuiltinInstallApi api = GirlsBuiltinInstallApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    await expectLater(
      api.installNovelEditor(
        accessToken: 'owner-token',
        groupId: _groupId,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('already-installed conflict is preserved instead of treated as success', () async {
    final MockClient client = MockClient(
      (http.Request request) async => _json(
        409,
        const <String, Object?>{
          'error': 'builtin_already_installed',
          'message': 'このビルトインアプリはすでに入っています。',
        },
      ),
    );
    final GirlsBuiltinInstallApi api = GirlsBuiltinInstallApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    await expectLater(
      api.installNovelEditor(
        accessToken: 'owner-token',
        groupId: _groupId,
      ),
      throwsA(
        isA<ApiException>()
            .having((ApiException error) => error.statusCode, 'statusCode', 409)
            .having(
              (ApiException error) => error.code,
              'code',
              'builtin_already_installed',
            ),
      ),
    );
  });
}
