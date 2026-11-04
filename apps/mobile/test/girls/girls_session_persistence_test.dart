import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/api.dart';
import 'package:minapp_mobile/girls/girls_community.dart';
import 'package:minapp_mobile/girls/girls_session_store.dart';
import 'package:minapp_mobile/girls/hosted_girls_api.dart';

void main() {
  final Uri baseUri = Uri.parse('https://girls-api.example.com');

  test('login verifies the community before saving the refresh token',
      () async {
    final _MemoryGirlsSessionStore sessionStore = _MemoryGirlsSessionStore();
    int requestCount = 0;
    final HostedGirlsApi api = HostedGirlsApi(
      baseUri: baseUri,
      sessionStore: sessionStore,
      client: MockClient((http.Request request) async {
        requestCount += 1;
        if (requestCount == 1) {
          expect(request.method, 'POST');
          expect(request.url.path, '/auth/login');
          expect(
            jsonDecode(request.body),
            <String, Object?>{'login_id': 'honey', 'password': 'secret12'},
          );
          return _authenticated(
            accessToken: 'access-1',
            refreshToken: 'refresh-1',
          );
        }
        if (requestCount == 2) {
          expect(request.method, 'GET');
          expect(request.url.path, '/hosted/groups');
          expect(request.headers['authorization'], 'Bearer access-1');
          expect(sessionStore.writeCount, 0);
          return _groupsResponse();
        }
        fail('Unexpected request #$requestCount: ${request.url}');
      }),
    );

    final AuthResult result = await api.login('honey', 'secret12');

    expect(result, isA<AuthenticatedSession>());
    expect((result as AuthenticatedSession).accessToken, 'access-1');
    expect(sessionStore.refreshToken, 'refresh-1');
    expect(sessionStore.writeCount, 1);
    expect(requestCount, 2);
  });

  test('restore verifies the community and preserves the refresh token',
      () async {
    final _MemoryGirlsSessionStore sessionStore = _MemoryGirlsSessionStore(
      refreshToken: 'refresh-saved',
    );
    int requestCount = 0;
    final HostedGirlsApi api = HostedGirlsApi(
      baseUri: baseUri,
      sessionStore: sessionStore,
      client: MockClient((http.Request request) async {
        requestCount += 1;
        if (requestCount == 1) {
          expect(request.method, 'POST');
          expect(request.url.path, '/auth/refresh');
          return _authenticated(accessToken: 'access-restored');
        }
        if (requestCount == 2) {
          expect(request.method, 'GET');
          expect(request.url.path, '/hosted/groups');
          return _groupsResponse();
        }
        fail('Unexpected request #$requestCount: ${request.url}');
      }),
    );

    final AuthenticatedSession? session = await api.restoreSession();

    expect(session?.accessToken, 'access-restored');
    expect(sessionStore.refreshToken, 'refresh-saved');
    expect(sessionStore.clearCount, 0);
    expect(requestCount, 2);
  });

  test('community lookup failure leaves login uncommitted', () async {
    final _MemoryGirlsSessionStore sessionStore = _MemoryGirlsSessionStore();
    int requestCount = 0;
    final HostedGirlsApi api = HostedGirlsApi(
      baseUri: baseUri,
      sessionStore: sessionStore,
      client: MockClient((http.Request request) async {
        requestCount += 1;
        if (requestCount == 1) {
          return _authenticated(
            accessToken: 'access-new',
            refreshToken: 'refresh-new',
          );
        }
        if (requestCount == 2) {
          return _jsonResponse(
            <String, Object?>{
              'error': 'temporary_failure',
              'message': 'group service unavailable',
            },
            statusCode: 503,
          );
        }
        fail('Unexpected request #$requestCount: ${request.url}');
      }),
    );

    await expectLater(
      api.login('honey', 'secret12'),
      throwsA(
        isA<ApiException>()
            .having((ApiException e) => e.statusCode, 'statusCode', 503)
            .having((ApiException e) => e.code, 'code', 'temporary_failure'),
      ),
    );
    expect(sessionStore.refreshToken, isNull);
    expect(sessionStore.writeCount, 0);
    expect(requestCount, 2);
  });

  test('logout only clears the saved login', () async {
    final _MemoryGirlsSessionStore sessionStore = _MemoryGirlsSessionStore(
      refreshToken: 'refresh-saved',
    );
    final HostedGirlsApi api = HostedGirlsApi(
      baseUri: baseUri,
      sessionStore: sessionStore,
      client: MockClient((http.Request request) async {
        fail('Logout must not make a network request.');
      }),
    );

    await api.logout();

    expect(sessionStore.refreshToken, isNull);
    expect(sessionStore.clearCount, 1);
  });

  test('explicit invalid_refresh_token clears saved login', () async {
    final _MemoryGirlsSessionStore sessionStore = _MemoryGirlsSessionStore(
      refreshToken: 'refresh-expired',
    );
    final HostedGirlsApi api = HostedGirlsApi(
      baseUri: baseUri,
      sessionStore: sessionStore,
      client: MockClient((http.Request request) async => _jsonResponse(
            <String, Object?>{
              'error': 'invalid_refresh_token',
              'message': 'ログイン期限が切れました。',
            },
            statusCode: 401,
          )),
    );

    expect(await api.restoreSession(), isNull);
    expect(sessionStore.refreshToken, isNull);
    expect(sessionStore.clearCount, 1);
  });

  test('transient refresh failure preserves saved login', () async {
    final _MemoryGirlsSessionStore sessionStore = _MemoryGirlsSessionStore(
      refreshToken: 'refresh-keep-me',
    );
    final HostedGirlsApi api = HostedGirlsApi(
      baseUri: baseUri,
      sessionStore: sessionStore,
      client: MockClient((http.Request request) async => _jsonResponse(
            <String, Object?>{
              'error': 'temporary_failure',
              'message': 'temporarily unavailable',
            },
            statusCode: 503,
          )),
    );

    await expectLater(api.restoreSession(), throwsA(isA<ApiException>()));
    expect(sessionStore.refreshToken, 'refresh-keep-me');
    expect(sessionStore.clearCount, 0);
  });

  test('login without refresh token enters a temporary session', () async {
    final _MemoryGirlsSessionStore sessionStore = _MemoryGirlsSessionStore(
      refreshToken: 'previous-account-token',
    );
    int requestCount = 0;
    final HostedGirlsApi api = HostedGirlsApi(
      baseUri: baseUri,
      sessionStore: sessionStore,
      client: MockClient((http.Request request) async {
        requestCount += 1;
        if (requestCount == 1) {
          return _authenticated(accessToken: 'access-1');
        }
        if (requestCount == 2) return _groupsResponse();
        fail('Unexpected request #$requestCount: ${request.url}');
      }),
    );

    final AuthResult result = await api.login('honey', 'secret12');
    expect(result, isA<AuthenticatedSession>());
    expect(sessionStore.writeCount, 0);
    expect(sessionStore.clearCount, 1);
    expect(sessionStore.refreshToken, isNull);
    expect(requestCount, 2);
  });

  test('login rejects an explicitly invalid refresh token', () async {
    final _MemoryGirlsSessionStore sessionStore = _MemoryGirlsSessionStore();
    final HostedGirlsApi api = HostedGirlsApi(
      baseUri: baseUri,
      sessionStore: sessionStore,
      client: MockClient((http.Request request) async => _jsonResponse(
            <String, Object?>{
              'state': 'authenticated',
              'access_token': 'access-1',
              'token_type': 'Bearer',
              'expires_in': 3600,
              'refresh_token': '',
            },
          )),
    );

    await expectLater(api.login('honey', 'secret12'), throwsFormatException);
    expect(sessionStore.writeCount, 0);
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

http.Response _authenticated({
  required String accessToken,
  String? refreshToken,
}) {
  return _jsonResponse(<String, Object?>{
    'state': 'authenticated',
    'access_token': accessToken,
    'token_type': 'Bearer',
    'expires_in': 3600,
    if (refreshToken != null) 'refresh_token': refreshToken,
  });
}

http.Response _groupsResponse() {
  return _jsonResponse(<String, Object?>{
    'groups': <Object?>[
      <String, Object?>{
        'group_id': girlsCommunityGroupId,
        'name': girlsCommunityGroupName,
        'role': 'member',
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
