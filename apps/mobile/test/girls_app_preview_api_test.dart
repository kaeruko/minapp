import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/api.dart';
import 'package:minapp_mobile/girls/girls_app_preview_api.dart';
import 'package:minapp_mobile/hosted_runtime_bridge.dart';

const String _groupId = '22222222222222222222222222222222';
const String _appId = '33333333333333333333333333333333';
const String _contentToken = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const String _previewToken = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';
const String _runtimeToken = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
const String _refreshedRuntimeToken =
    'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD';

http.Response _json(int status, Map<String, Object?> body) => http.Response(
      jsonEncode(body),
      status,
      headers: const <String, String>{'content-type': 'application/json'},
    );

class _ExpiringRuntimeTransport implements HostedRuntimeTransport {
  final List<String> tokens = <String>[];

  Future<Object?> _handle(String token) async {
    tokens.add(token);
    if (token == _runtimeToken) {
      throw const ApiException(
        statusCode: 404,
        code: 'runtime_session_not_found',
        message: 'Runtime session is invalid or expired.',
      );
    }
    if (token == _refreshedRuntimeToken) {
      return <String, Object?>{'ok': true};
    }
    fail('Unexpected Runtime token: $token');
  }

  @override
  Future<Object?> getState(String runtimeToken, String key) =>
      _handle(runtimeToken);

  @override
  Future<Object?> setState(String runtimeToken, String key, Object? value) =>
      _handle(runtimeToken);

  @override
  Future<void> deleteState(String runtimeToken, String key) async {
    await _handle(runtimeToken);
  }

  @override
  Future<Object?> getUserState(String runtimeToken, String key) =>
      _handle(runtimeToken);

  @override
  Future<Object?> setUserState(
    String runtimeToken,
    String key,
    Object? value,
  ) =>
      _handle(runtimeToken);

  @override
  Future<void> deleteUserState(String runtimeToken, String key) async {
    await _handle(runtimeToken);
  }
}

void main() {
  test('published self-test uses published-session and does not call launch-session', () async {
    final List<String> paths = <String>[];
    final MockClient client = MockClient((http.Request request) async {
      paths.add(request.url.path);
      expect(request.method, 'POST');
      expect(request.headers['authorization'], 'Bearer owner-token');
      expect(request.body, '{}');
      if (request.url.path.endsWith('/published-session')) {
        return _json(201, <String, Object?>{
          'content_path': '/hosted/content/$_contentToken/index.html',
          'published_version': 4,
          'expires_in': 600,
        });
      }
      if (request.url.path.endsWith('/runtime-session')) {
        return _json(201, <String, Object?>{
          'token': _runtimeToken,
          'expires_in': 600,
        });
      }
      fail('Unexpected request: ${request.url}');
    });
    final GirlsAppPreviewApi api = GirlsAppPreviewApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    final GirlsAppTestSession session = await api.createPublishedTest(
      accessToken: 'owner-token',
      groupId: _groupId,
      appId: _appId,
    );

    expect(
      session.contentUri.toString(),
      'https://hosted.example.test/hosted/content/$_contentToken/index.html',
    );
    expect(session.publishedVersion, 4);
    expect(session.sourceRevision, isNull);
    expect(session.runtimeToken, _runtimeToken);
    expect(
      paths,
      <String>[
        '/hosted/groups/$_groupId/apps/$_appId/published-session',
        '/hosted/groups/$_groupId/apps/$_appId/runtime-session',
      ],
    );
    expect(
      paths.where((String path) => path.contains('/launch-session')),
      isEmpty,
    );
  });

  test('draft preview receives its isolated runtime capability from preview-session', () async {
    final List<String> paths = <String>[];
    final MockClient client = MockClient((http.Request request) async {
      paths.add(request.url.path);
      expect(request.method, 'POST');
      expect(request.headers['authorization'], 'Bearer owner-token');
      expect(request.body, '{}');
      if (request.url.path == '/hosted/my/apps/$_appId/preview-session') {
        return _json(201, <String, Object?>{
          'app_id': _appId,
          'group_id': _groupId,
          'source_revision': 7,
          'content_path': '/hosted/preview/$_previewToken/index.html',
          'expires_in': 600,
          'runtime_token': _runtimeToken,
          'runtime_expires_in': 600,
        });
      }
      fail('Unexpected request: ${request.url}');
    });
    final GirlsAppPreviewApi api = GirlsAppPreviewApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );

    final GirlsAppTestSession session = await api.createDraftPreview(
      accessToken: 'owner-token',
      groupId: _groupId,
      appId: _appId,
    );

    expect(
      session.contentUri.toString(),
      'https://hosted.example.test/hosted/preview/$_previewToken/index.html',
    );
    expect(session.sourceRevision, 7);
    expect(session.publishedVersion, isNull);
    expect(session.runtimeToken, _runtimeToken);
    expect(session.runtimeExpiresIn, 600);
    expect(
      paths,
      <String>['/hosted/my/apps/$_appId/preview-session'],
    );
  });

  test('draft preview Runtime refresh retries once with the same preview scope', () async {
    int refreshRequests = 0;
    final MockClient client = MockClient((http.Request request) async {
      expect(
        request.url.path,
        '/hosted/my/apps/$_appId/preview-runtime-session',
      );
      expect(request.method, 'POST');
      expect(request.headers['authorization'], 'Bearer owner-token');
      expect(
        jsonDecode(request.body),
        <String, Object?>{'runtime_token': _runtimeToken},
      );
      refreshRequests += 1;
      return _json(201, <String, Object?>{
        'runtime_token': _refreshedRuntimeToken,
        'runtime_expires_in': 600,
      });
    });
    final GirlsAppPreviewApi api = GirlsAppPreviewApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: client,
    );
    final _ExpiringRuntimeTransport delegate = _ExpiringRuntimeTransport();
    final GirlsPreviewRuntimeTransport transport = GirlsPreviewRuntimeTransport(
      delegate: delegate,
      previewApi: api,
      accessToken: 'owner-token',
      groupId: _groupId,
      appId: _appId,
      runtimeToken: _runtimeToken,
      groupScope: false,
    );

    final Object? saved = await transport.setState(
      _runtimeToken,
      'minappchi_pet_v1',
      <String, Object?>{'fullness': 4},
    );
    expect(saved, <String, Object?>{'ok': true});
    expect(
      delegate.tokens,
      <String>[_runtimeToken, _refreshedRuntimeToken],
    );
    expect(refreshRequests, 1);

    final Object? loaded = await transport.getState(
      _runtimeToken,
      'minappchi_pet_v1',
    );
    expect(loaded, <String, Object?>{'ok': true});
    expect(
      delegate.tokens,
      <String>[
        _runtimeToken,
        _refreshedRuntimeToken,
        _refreshedRuntimeToken,
      ],
    );
    expect(refreshRequests, 1);
  });

}
