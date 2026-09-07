import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/hosted_runtime_bridge.dart';

const String _runtimeToken = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';

class FakePrivateRuntimeTransport
    implements HostedRuntimeTransport, HostedUserStateTransport {
  final List<String> calls = <String>[];
  Object? sharedValue;
  Object? userValue;

  @override
  Future<void> deleteState(String runtimeToken, String key) async {
    calls.add('state.delete:$runtimeToken:$key');
    sharedValue = null;
  }

  @override
  Future<Object?> getState(String runtimeToken, String key) async {
    calls.add('state.get:$runtimeToken:$key');
    return sharedValue;
  }

  @override
  Future<Object?> setState(String runtimeToken, String key, Object? value) async {
    calls.add('state.set:$runtimeToken:$key');
    sharedValue = value;
    return value;
  }

  @override
  Future<void> deleteUserState(String runtimeToken, String key) async {
    calls.add('userState.delete:$runtimeToken:$key');
    userValue = null;
  }

  @override
  Future<Object?> getUserState(String runtimeToken, String key) async {
    calls.add('userState.get:$runtimeToken:$key');
    return userValue;
  }

  @override
  Future<Object?> setUserState(
    String runtimeToken,
    String key,
    Object? value,
  ) async {
    calls.add('userState.set:$runtimeToken:$key');
    userValue = value;
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
  test('userState bridge is distinct from shared state', () async {
    final FakePrivateRuntimeTransport transport = FakePrivateRuntimeTransport();
    final HostedBridgeSession session = HostedBridgeSession(
      transport: transport,
      runtimeToken: _runtimeToken,
    );

    await session.handleMessage(
      _request(
        id: '1',
        method: 'state.set',
        key: 'progress',
        value: <String, Object?>{'scope': 'shared'},
        includeValue: true,
      ),
    );
    await session.handleMessage(
      _request(
        id: '2',
        method: 'userState.set',
        key: 'progress',
        value: <String, Object?>{'scope': 'user'},
        includeValue: true,
      ),
    );

    final Map<String, Object?> shared = await session.handleMessage(
      _request(id: '3', method: 'state.get', key: 'progress'),
    );
    final Map<String, Object?> user = await session.handleMessage(
      _request(id: '4', method: 'userState.get', key: 'progress'),
    );

    expect(shared['result'], <String, Object?>{'scope': 'shared'});
    expect(user['result'], <String, Object?>{'scope': 'user'});
    expect(
      transport.calls,
      <String>[
        'state.set:$_runtimeToken:progress',
        'userState.set:$_runtimeToken:progress',
        'state.get:$_runtimeToken:progress',
        'userState.get:$_runtimeToken:progress',
      ],
    );
  });

  test('HostedApiClient uses the private user-state endpoint', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(
        request.url.path,
        '/hosted/runtime/$_runtimeToken/user-state/progress',
      );
      expect(request.method, 'POST');
      expect(
        jsonDecode(request.body),
        <String, Object?>{
          'value': <String, Object?>{'scene': 'start'},
        },
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'key': 'progress',
          'value': <String, Object?>{'scene': 'start'},
          'updated_at': '2026-09-06T08:00:00Z',
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final HostedApiClient api = HostedApiClient(
      baseUri: Uri.parse('https://hosted.example.test/'),
      client: client,
    );

    expect(
      await api.setUserState(
        _runtimeToken,
        'progress',
        <String, Object?>{'scene': 'start'},
      ),
      <String, Object?>{'scene': 'start'},
    );
  });

  test('bootstrap exposes both state scopes without credentials', () {
    const String script = HostedBridgeProtocol.bootstrapJavaScript;
    expect(script, contains("send('state.get'"));
    expect(script, contains("send('userState.get'"));
    expect(script, contains('version: VERSION, state, userState'));
    expect(script.toLowerCase(), isNot(contains('runtime_token')));
    expect(script.toLowerCase(), isNot(contains('user_id')));
  });
}
