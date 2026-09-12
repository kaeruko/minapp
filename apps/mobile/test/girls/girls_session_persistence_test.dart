import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/api.dart';
import 'package:minapp_mobile/girls/girls_session_store.dart';
import 'package:minapp_mobile/girls/hosted_girls_api.dart';

void main() {
  final Uri baseUri = Uri.parse('https://girls-api.example.com');

  test('login onboards groups before saving refresh token', () async {
    final _MemoryGirlsSessionStore store = _MemoryGirlsSessionStore();
    int requestCount = 0;
    final MockClient client = MockClient((http.Request request) async {
      requestCount += 1;
      if (requestCount == 1) {
        expect(request.method, 'POST');
        expect(request.url, Uri.parse('https://girls-api.example.com/auth/login'));
        expect(
          jsonDecode(request.body),
          <String, Object?>{'login_id': 'honey', 'password': 'secret12'},
        );
        expect(store.writeCount, 0);
        return _jsonResponse(<String, Object?>{
          'state': 'authenticated',
          'access_token': 'access-1',
          'token_type': 'Bearer',
          'expires_in': 3600,
          'refresh_token': 'refresh-1',
        });
      }
      if (requestCount == 2) {
        expect(request.method, 'GET');
        expect(
          request.url,
          Uri.parse('https://girls-api.example.com/hosted/groups'),
        );
        expect(request.headers['Authorization'], 'Bearer access-1');
        expect(store.writeCount, 0);
        return _existingGroupsResponse();
      }
      fail('Unexpected request #$requestCount: ${request.method} ${request.url}');
    });
    final HostedGirlsApi api = HostedGirlsApi(
      baseUri: baseUri,
      client: client,
      sessionStore: store,
    );

    final AuthResult result = await api.login('honey', 'secret12');

    expect(result, isA<AuthenticatedSession>());
    expect((result as AuthenticatedSession).accessToken, 'access-1');
    expect(store.refreshToken, 'refresh-1');
    expect(store.writeCount, 1);
    expect(requestCount, 2);
  });

  test('restore exchanges token and verifies initial group state', () async {
    final _MemoryGirlsSessionStore store = _MemoryGirlsSessionStore(
      refreshToken: 'refresh-saved',
    );
    int requestCount = 0;
    final MockClient client = MockClient((http.Request request) async {
      requestCount += 1;
      if (requestCount == 1) {
        expect(request.method, 'POST');
        expect(request.url, Uri.parse('https://girls-api.example.com/auth/refresh'));
        expect(
          jsonDecode(request.body),
          <String, Object?>{'refresh_token': 'refresh-saved'},
        );
        return _jsonResponse(<String, Object?>{
          'state': 'authenticated',
          'access_token': 'access-restored',
          'token_type': 'Bearer',
          'expires_in': 3600,
        });
      }
      if (requestCount == 2) {
        expect(request.method, 'GET');
        expect(
          request.url,
          Uri.parse('https://girls-api.example.com/hosted/groups'),
        );
        expect(request.headers['Authorization'], 'Bearer access-restored');
        return _existingGroupsResponse();
      }
      fail('Unexpected request #$requestCount: ${request.method} ${request.url}');
    });
    final HostedGirlsApi api = HostedGirlsApi(
      baseUri: baseUri,
      client: client,
      sessionStore: store,
    );

    final AuthenticatedSession? session = await api.restoreSession();

    expect(session, isNotNull);
    expect(session!.accessToken, 'access-restored');
    expect(store.refreshToken, 'refresh-saved');
    expect(store.clearCount, 0);
    expect(requestCount, 2);
  });

  test('empty account creates starter group before login is committed', () async {
    final _MemoryGirlsSessionStore store = _MemoryGirlsSessionStore();
    int requestCount = 0;
    final MockClient client = MockClient((http.Request request) async {
      requestCount += 1;
      if (requestCount == 1) {
        return _jsonResponse(<String, Object?>{
          'state': 'authenticated',
          'access_token': 'access-new',
          'token_type': 'Bearer',
          'expires_in': 3600,
          'refresh_token': 'refresh-new',
        });
      }
      if (requestCount == 2) {
        expect(request.method, 'GET');
        expect(
          request.url,
          Uri.parse('https://girls-api.example.com/hosted/groups'),
        );
        expect(store.writeCount, 0);
        return _jsonResponse(<String, Object?>{'groups': <Object?>[]});
      }
      if (requestCount == 3) {
        expect(request.method, 'POST');
        expect(
          request.url,
          Uri.parse('https://girls-api.example.com/hosted/groups'),
        );
        expect(jsonDecode(request.body), <String, Object?>{'name': 'はじめのグループ'});
        expect(store.writeCount, 0);
        return _jsonResponse(<String, Object?>{
          'group_id': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          'name': 'はじめのグループ',
          'role': 'owner',
          'status': 'active',
        }, statusCode: 201);
      }
      fail('Unexpected request #$requestCount: ${request.method} ${request.url}');
    });
    final HostedGirlsApi api = HostedGirlsApi(
      baseUri: baseUri,
      client: client,
      sessionStore: store,
    );

    final AuthResult result = await api.login('honey', 'secret12');

    expect(result, isA<AuthenticatedSession>());
    expect(store.refreshToken, 'refresh-new');
    expect(store.writeCount, 1);
    expect(requestCount, 3);
  });

  test('starter group failure leaves login uncommitted', () async {
    final _MemoryGirlsSessionStore store = _MemoryGirlsSessionStore();
    int requestCount = 0;
    final MockClient client = MockClient((http.Request request) async {
      requestCount += 1;
      if (requestCount == 1) {
        return _jsonResponse(<String, Object?>{
          'state': 'authenticated',
          'access_token': 'access-new',
          'token_type': 'Bearer',
          'expires_in': 3600,
          'refresh_token': 'refresh-new',
        });
      }
      if (requestCount == 2) {
        return _jsonResponse(<String, Object?>{'groups': <Object?>[]});
      }
      if (requestCount == 3) {
        return _jsonResponse(
          <String, Object?>{
            'error': 'temporary_failure',
            'message': 'group service unavailable',
          },
          statusCode: 503,
        );
      }
      fail('Unexpected request #$requestCount: ${request.method} ${request.url}');
    });
    final HostedGirlsApi api = HostedGirlsApi(
      baseUri: baseUri,
      client: client,
      sessionStore: store,
    );

    await expectLater(
      api.login('honey', 'secret12'),
      throwsA(
        isA<ApiException>()
            .having((ApiException e) => e.statusCode, 'statusCode', 503)
            .having((ApiException e) => e.code, 'code', 'temporary_failure'),
      ),
    );

    expect(store.refreshToken, isNull);
    expect(store.writeCount, 0);
    expect(requestCount, 3);
  });

  test('explicit invalid_refresh_token clears saved login', () async {
    final _MemoryGirlsSessionStore store = _MemoryGirlsSessionStore(
      refreshToken: 'refresh-expired',
    );
    final MockClient client = MockClient((http.Request request) async {
      return _jsonResponse(
        <String, Object?>{
          'error': 'invalid_refresh_token',
          'message': 'ログイン期限が切れました。もう一度ログインしてください。',
        },
        statusCode: 401,
      );
    });
    final HostedGirlsApi api = HostedGirlsApi(
      baseUri: baseUri,
      client: client,
      sessionStore: store,
    );

    final AuthenticatedSession? session = await api.restoreSession();

    expect(session, isNull);
    expect(store.refreshToken, isNull);
    expect(store.clearCount, 1);
  });

  test('transient refresh failure preserves saved login and propagates error',
      () async {
    final _MemoryGirlsSessionStore store = _MemoryGirlsSessionStore(
      refreshToken: 'refresh-keep-me',
    );
    final MockClient client = MockClient((http.Request request) async {
      return _jsonResponse(
        <String, Object?>{
          'error': 'temporary_failure',
          'message': 'temporarily unavailable',
        },
        statusCode: 503,
      );
    });
    final HostedGirlsApi api = HostedGirlsApi(
      baseUri: baseUri,
      client: client,
      sessionStore: store,
    );

    await expectLater(
      api.restoreSession(),
      throwsA(
        isA<ApiException>()
            .having((ApiException e) => e.statusCode, 'statusCode', 503)
            .having((ApiException e) => e.code, 'code', 'temporary_failure'),
      ),
    );

    expect(store.refreshToken, 'refresh-keep-me');
    expect(store.clearCount, 0);
  });

  test('authenticated login without refresh_token fails closed', () async {
    final _MemoryGirlsSessionStore store = _MemoryGirlsSessionStore();
    final MockClient client = MockClient((http.Request request) async {
      return _jsonResponse(<String, Object?>{
        'state': 'authenticated',
        'access_token': 'access-1',
        'token_type': 'Bearer',
        'expires_in': 3600,
      });
    });
    final HostedGirlsApi api = HostedGirlsApi(
      baseUri: baseUri,
      client: client,
      sessionStore: store,
    );

    await expectLater(api.login('honey', 'secret12'), throwsFormatException);
    expect(store.writeCount, 0);
  });
}

class _MemoryGirlsSessionStore implements GirlsSessionStore {
  _MemoryGirlsSessionStore({this.refreshToken});

  String? refreshToken;
  int writeCount = 0;
  int clearCount = 0;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> writeRefreshToken(String refreshToken) async {
    writeCount += 1;
    this.refreshToken = refreshToken;
  }

  @override
  Future<void> clearRefreshToken() async {
    clearCount += 1;
    refreshToken = null;
  }
}

http.Response _existingGroupsResponse() {
  return _jsonResponse(<String, Object?>{
    'groups': <Object?>[
      <String, Object?>{
        'group_id': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'name': '既存グループ',
        'role': 'owner',
        'status': 'active',
      },
    ],
  });
}

http.Response _jsonResponse(
  Map<String, Object?> body, {
  int statusCode = 200,
}) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: const <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  );
}
