import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/api.dart';
import 'package:minapp_mobile/app_webview.dart';
import 'package:minapp_mobile/hosted_runtime_bridge.dart';

const String _runtimeToken = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
const String _contentToken = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const String _otherContentToken = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';
const String _groupId = '22222222222222222222222222222222';
const String _appId = '33333333333333333333333333333333';

class FakeRuntimeTransport implements HostedRuntimeTransport {
  final List<String> calls = <String>[];
  Object? storedValue;
  ApiException? failure;
  Completer<Object?>? getCompleter;

  @override
  Future<void> deleteState(String runtimeToken, String key) async {
    calls.add('delete:$runtimeToken:$key');
    final ApiException? error = failure;
    if (error != null) throw error;
    storedValue = null;
  }

  @override
  Future<Object?> getState(String runtimeToken, String key) async {
    calls.add('get:$runtimeToken:$key');
    final ApiException? error = failure;
    if (error != null) throw error;
    final Completer<Object?>? completer = getCompleter;
    if (completer != null) return completer.future;
    return storedValue;
  }

  @override
  Future<Object?> setState(String runtimeToken, String key, Object? value) async {
    calls.add('set:$runtimeToken:$key');
    final ApiException? error = failure;
    if (error != null) throw error;
    storedValue = value;
    return value;
  }
}

String _request({
  required String id,
  required String method,
  required String key,
  Object? value,
  bool includeValue = false,
}) {
  final Map<String, Object?> payload = <String, Object?>{
    'version': 1,
    'id': id,
    'method': method,
    'key': key,
  };
  if (includeValue) payload['value'] = value;
  return jsonEncode(payload);
}

void main() {
  group('HostedApiClient launch contract', () {
    test('decodes exact launch response and sends Cognito token only to parent API', () async {
      final MockClient client = MockClient((http.Request request) async {
        expect(request.method, 'POST');
        expect(
          request.url.path,
          '/hosted/groups/$_groupId/apps/$_appId/launch-session',
        );
        expect(request.headers['Authorization'], 'Bearer parent-cognito-token');
        expect(jsonDecode(request.body), <String, Object?>{});
        return http.Response(
          jsonEncode(<String, Object?>{
            'content_path': '/hosted/content/$_contentToken/index.html',
            'content_expires_in': 600,
            'runtime_token': _runtimeToken,
            'runtime_expires_in': 600,
            'published_version': 2,
          }),
          201,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
      final HostedApiClient api = HostedApiClient(
        baseUri: Uri.parse('https://hosted.example.test/'),
        client: client,
      );

      final HostedLaunchGrant launch = await api.createLaunch(
        accessToken: 'parent-cognito-token',
        groupId: _groupId,
        appId: _appId,
      );

      expect(
        launch.contentUri,
        Uri.parse('https://hosted.example.test/hosted/content/$_contentToken/index.html'),
      );
      expect(launch.runtimeToken, _runtimeToken);
      expect(launch.runtimeExpiresIn, 600);
    });

    test('rejects unknown launch response fields instead of accepting protocol drift', () async {
      final MockClient client = MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<String, Object?>{
            'content_path': '/hosted/content/$_contentToken/index.html',
            'content_expires_in': 600,
            'runtime_token': _runtimeToken,
            'runtime_expires_in': 600,
            'published_version': 1,
            'access_token': 'must-not-be-accepted',
          }),
          201,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
      final HostedApiClient api = HostedApiClient(
        baseUri: Uri.parse('https://hosted.example.test/'),
        client: client,
      );

      await expectLater(
        api.createLaunch(
          accessToken: 'parent-token',
          groupId: _groupId,
          appId: _appId,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('maps backend Runtime errors to ApiException without changing code or status', () async {
      final MockClient client = MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<String, Object?>{
            'error': 'runtime_session_not_found',
            'message': 'Runtime session is invalid or expired.',
          }),
          404,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
      final HostedApiClient api = HostedApiClient(
        baseUri: Uri.parse('https://hosted.example.test/'),
        client: client,
      );

      await expectLater(
        api.getState(_runtimeToken, 'chapter'),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.statusCode, 'statusCode', 404)
              .having((ApiException e) => e.code, 'code', 'runtime_session_not_found')
              .having(
                (ApiException e) => e.message,
                'message',
                'Runtime session is invalid or expired.',
              ),
        ),
      );
    });

    test('serializes Runtime set value exactly once through the native transport', () async {
      final MockClient client = MockClient((http.Request request) async {
        expect(request.headers.containsKey('Authorization'), isFalse);
        expect(
          jsonDecode(request.body),
          <String, Object?>{
            'value': <String, Object?>{
              'page': 3,
              'flags': <Object?>[true, null, 'x'],
            },
          },
        );
        return http.Response(
          jsonEncode(<String, Object?>{
            'key': 'chapter',
            'value': <String, Object?>{
              'page': 3,
              'flags': <Object?>[true, null, 'x'],
            },
            'updated_at': '2026-08-28T00:00:00Z',
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
      final HostedApiClient api = HostedApiClient(
        baseUri: Uri.parse('https://hosted.example.test/'),
        client: client,
      );

      final Object? result = await api.setState(
        _runtimeToken,
        'chapter',
        <String, Object?>{
          'page': 3,
          'flags': <Object?>[true, null, 'x'],
        },
      );
      expect(result, isA<Map<String, Object?>>());
    });
  });

  group('Hosted bridge protocol', () {
    test('set/get/delete are Promise-style request methods with strict fields', () async {
      final FakeRuntimeTransport transport = FakeRuntimeTransport();
      final HostedBridgeSession session = HostedBridgeSession(
        transport: transport,
        runtimeToken: _runtimeToken,
      );

      final Map<String, Object?> setResponse = await session.handleMessage(
        _request(
          id: '1',
          method: 'state.set',
          key: 'chapter',
          value: <String, Object?>{'page': 3},
          includeValue: true,
        ),
      );
      final Map<String, Object?> getResponse = await session.handleMessage(
        _request(id: '2', method: 'state.get', key: 'chapter'),
      );
      final Map<String, Object?> deleteResponse = await session.handleMessage(
        _request(id: '3', method: 'state.delete', key: 'chapter'),
      );

      expect(setResponse['ok'], isTrue);
      expect(getResponse['result'], <String, Object?>{'page': 3});
      expect(deleteResponse['result'], isNull);
      expect(transport.calls, <String>[
        'set:$_runtimeToken:chapter',
        'get:$_runtimeToken:chapter',
        'delete:$_runtimeToken:chapter',
      ]);
    });

    test('rejects malformed JSON, unknown methods, extra fields, and invalid keys', () async {
      final FakeRuntimeTransport transport = FakeRuntimeTransport();
      final HostedBridgeSession session = HostedBridgeSession(
        transport: transport,
        runtimeToken: _runtimeToken,
      );

      final Map<String, Object?> malformed = await session.handleMessage('{');
      expect(
        (malformed['error']! as Map<String, Object?>)['code'],
        'invalid_bridge_request',
      );

      final Map<String, Object?> unknown = await session.handleMessage(
        _request(id: 'u1', method: 'state.clearAll', key: 'chapter'),
      );
      expect(
        (unknown['error']! as Map<String, Object?>)['code'],
        'unsupported_bridge_method',
      );

      final Map<String, Object?> extra = await session.handleMessage(
        jsonEncode(<String, Object?>{
          'version': 1,
          'id': 'u2',
          'method': 'state.get',
          'key': 'chapter',
          'runtime_token': 'attacker-controlled',
        }),
      );
      expect(
        (extra['error']! as Map<String, Object?>)['code'],
        'invalid_bridge_request',
      );

      final Map<String, Object?> invalidKey = await session.handleMessage(
        _request(id: 'u3', method: 'state.get', key: '../chapter'),
      );
      expect(
        (invalidKey['error']! as Map<String, Object?>)['code'],
        'invalid_state_key',
      );
      expect(transport.calls, isEmpty);
    });

    test('preserves backend HTTP status, error code, and message for JavaScript', () async {
      final FakeRuntimeTransport transport = FakeRuntimeTransport()
        ..failure = const ApiException(
          statusCode: 429,
          code: 'runtime_request_limit_reached',
          message: 'Runtime request quota exceeded.',
        );
      final HostedBridgeSession session = HostedBridgeSession(
        transport: transport,
        runtimeToken: _runtimeToken,
      );

      final Map<String, Object?> response = await session.handleMessage(
        _request(id: 'quota1', method: 'state.get', key: 'chapter'),
      );
      final Map<String, Object?> error = response['error']! as Map<String, Object?>;
      expect(error['status'], 429);
      expect(error['code'], 'runtime_request_limit_reached');
      expect(error['message'], 'Runtime request quota exceeded.');
    });

    test('rejects a duplicate in-flight request id', () async {
      final Completer<Object?> completer = Completer<Object?>();
      final FakeRuntimeTransport transport = FakeRuntimeTransport()
        ..getCompleter = completer;
      final HostedBridgeSession session = HostedBridgeSession(
        transport: transport,
        runtimeToken: _runtimeToken,
      );
      final String request = _request(id: 'same1', method: 'state.get', key: 'chapter');

      final Future<Map<String, Object?>> first = session.handleMessage(request);
      await Future<void>.delayed(Duration.zero);
      final Map<String, Object?> duplicate = await session.handleMessage(request);
      expect(
        (duplicate['error']! as Map<String, Object?>)['code'],
        'duplicate_request_id',
      );

      completer.complete(<String, Object?>{'page': 3});
      expect((await first)['ok'], isTrue);
    });

    test('bootstrap contains no parent/runtime credential and is reinjected per finished document', () {
      const String script = HostedBridgeProtocol.bootstrapJavaScript;
      expect(script, contains('window.minapp'));
      expect(script, contains('minappready'));
      expect(script.toLowerCase(), isNot(contains('access_token')));
      expect(script.toLowerCase(), isNot(contains('refresh_token')));
      expect(script.toLowerCase(), isNot(contains('aws_access_key')));
      expect(script.toLowerCase(), isNot(contains('runtime_token')));
      expect(script, isNot(contains(_runtimeToken)));

      final HostedBridgeDocumentInjector injector = HostedBridgeDocumentInjector();
      expect(injector.scriptForFinishedDocument(), script);
      expect(injector.scriptForFinishedDocument(), script);
      expect(injector.finishedDocumentCount, 2);
    });
  });

  group('Hosted navigation boundary', () {
    test('allows only the current content capability path on the same HTTPS origin', () {
      final HostedContentNavigationPolicy policy = HostedContentNavigationPolicy(
        Uri.parse('https://hosted.example.test/hosted/content/$_contentToken/index.html'),
      );

      expect(
        policy.allows(
          Uri.parse('https://hosted.example.test/hosted/content/$_contentToken/assets/app.js'),
        ),
        isTrue,
      );
      expect(
        policy.allows(
          Uri.parse('https://hosted.example.test/hosted/content/$_otherContentToken/index.html'),
        ),
        isFalse,
      );
      expect(policy.allows(Uri.parse('https://evil.example/index.html')), isFalse);
      expect(policy.allows(Uri.parse('file:///tmp/index.html')), isFalse);
      expect(policy.allows(Uri.parse('javascript:alert(1)')), isFalse);
      expect(
        policy.allows(
          Uri.parse('https://user@hosted.example.test/hosted/content/$_contentToken/index.html'),
        ),
        isFalse,
      );
    });
  });

  test('dedicated/school AppWebViewPage contract remains available unchanged', () {
    final AppWebViewPage page = AppWebViewPage(
      title: 'Dedicated app',
      launchUrl: Uri.parse(
        'https://school.example.test/launch/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/index.html',
      ),
    );
    expect(page.title, 'Dedicated app');
    expect(page.launchUrl.pathSegments.first, 'launch');
  });
}
