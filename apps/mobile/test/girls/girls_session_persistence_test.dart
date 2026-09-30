import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/api.dart';
import 'package:minapp_mobile/girls/girls_current_group_store.dart';
import 'package:minapp_mobile/girls/girls_session_store.dart';
import 'package:minapp_mobile/girls/hosted_girls_api.dart';

void main() {
  final Uri baseUri = Uri.parse('https://girls-api.example.com');
  const String userA = '11111111111111111111111111111111';
  const String groupA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  test('login identifies account before restoring its remembered group', () async {
    final _MemoryGirlsSessionStore sessionStore = _MemoryGirlsSessionStore();
    final _MemoryCurrentGroupStore currentGroupStore =
        _MemoryCurrentGroupStore(remembered: <String, String>{userA: groupA});
    int requestCount = 0;
    final MockClient client = MockClient((http.Request request) async {
      requestCount += 1;
      switch (requestCount) {
        case 1:
          expect(request.method, 'POST');
          expect(
            request.url,
            Uri.parse('https://girls-api.example.com/auth/login'),
          );
          expect(
            jsonDecode(request.body),
            <String, Object?>{'login_id': 'honey', 'password': 'secret12'},
          );
          return _jsonResponse(<String, Object?>{
            'state': 'authenticated',
            'access_token': 'access-1',
            'token_type': 'Bearer',
            'expires_in': 3600,
            'refresh_token': 'refresh-1',
          });
        case 2:
          expect(request.method, 'GET');
          expect(
            request.url,
            Uri.parse('https://girls-api.example.com/hosted/me'),
          );
          expect(request.headers['Authorization'], 'Bearer access-1');
          return _meResponse(userA);
        case 3:
          expect(request.method, 'GET');
          expect(
            request.url,
            Uri.parse('https://girls-api.example.com/hosted/groups'),
          );
          expect(request.headers['Authorization'], 'Bearer access-1');
          return _groupsResponse(<Map<String, Object?>>[
            _group(groupA, '放課後イラスト部'),
            _group('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'マイグループ'),
          ]);
        default:
          fail(
            'Unexpected request #$requestCount: '
            '${request.method} ${request.url}',
          );
      }
    });
    final HostedGirlsApi api = HostedGirlsApi(
      baseUri: baseUri,
      client: client,
      sessionStore: sessionStore,
      currentGroupStore: currentGroupStore,
    );

    final AuthResult result = await api.login('honey', 'secret12');

    expect(result, isA<AuthenticatedSession>());
    expect((result as AuthenticatedSession).accessToken, 'access-1');
    expect(sessionStore.refreshToken, 'refresh-1');
    expect(sessionStore.writeCount, 1);
    expect(currentGroupStore.activeUserId, userA);
    expect(await currentGroupStore.load(), groupA);
    expect(requestCount, 3);
  });

  test('restore identifies account and restores its remembered group', () async {
    final _MemoryGirlsSessionStore sessionStore = _MemoryGirlsSessionStore(
      refreshToken: 'refresh-saved',
    );
    final _MemoryCurrentGroupStore currentGroupStore =
        _MemoryCurrentGroupStore(remembered: <String, String>{userA: groupA});
    int requestCount = 0;
    final MockClient client = MockClient((http.Request request) async {
      requestCount += 1;
      switch (requestCount) {
        case 1:
          expect(request.method, 'POST');
          expect(
            request.url,
            Uri.parse('https://girls-api.example.com/auth/refresh'),
          );
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
        case 2:
          expect(request.method, 'GET');
          expect(
            request.url,
            Uri.parse('https://girls-api.example.com/hosted/me'),
          );
          return _meResponse(userA);
        case 3:
          expect(request.method, 'GET');
          expect(
            request.url,
            Uri.parse('https://girls-api.example.com/hosted/groups'),
          );
          return _groupsResponse(<Map<String, Object?>>[
            _group(groupA, '放課後イラスト部'),
            _group('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'マイグループ'),
          ]);
        default:
          fail(
            'Unexpected request #$requestCount: '
            '${request.method} ${request.url}',
          );
      }
    });
    final HostedGirlsApi api = HostedGirlsApi(
      baseUri: baseUri,
      client: client,
      sessionStore: sessionStore,
      currentGroupStore: currentGroupStore,
    );

    final AuthenticatedSession? session = await api.restoreSession();

    expect(session, isNotNull);
    expect(session!.accessToken, 'access-restored');
    expect(sessionStore.refreshToken, 'refresh-saved');
    expect(sessionStore.clearCount, 0);
    expect(currentGroupStore.activeUserId, userA);
    expect(await currentGroupStore.load(), groupA);
    expect(requestCount, 3);
  });

  test('empty account creates and selects My Group before login is committed',
      () async {
    final _MemoryGirlsSessionStore sessionStore = _MemoryGirlsSessionStore();
    final _MemoryCurrentGroupStore currentGroupStore =
        _MemoryCurrentGroupStore();
    int requestCount = 0;
    final MockClient client = MockClient((http.Request request) async {
      requestCount += 1;
      switch (requestCount) {
        case 1:
          return _jsonResponse(<String, Object?>{
            'state': 'authenticated',
            'access_token': 'access-new',
            'token_type': 'Bearer',
            'expires_in': 3600,
            'refresh_token': 'refresh-new',
          });
        case 2:
          return _meResponse(userA);
        case 3:
          expect(request.method, 'GET');
          expect(
            request.url,
            Uri.parse('https://girls-api.example.com/hosted/groups'),
          );
          expect(sessionStore.writeCount, 0);
          return _groupsResponse(const <Map<String, Object?>>[]);
        case 4:
          expect(request.method, 'POST');
          expect(
            request.url,
            Uri.parse('https://girls-api.example.com/hosted/groups'),
          );
          expect(
            jsonDecode(request.body),
            <String, Object?>{'name': 'マイグループ'},
          );
          expect(sessionStore.writeCount, 0);
          return _jsonResponse(
            _group(
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
              'マイグループ',
            ),
            statusCode: 201,
          );
        default:
          fail(
            'Unexpected request #$requestCount: '
            '${request.method} ${request.url}',
          );
      }
    });
    final HostedGirlsApi api = HostedGirlsApi(
      baseUri: baseUri,
      client: client,
      sessionStore: sessionStore,
      currentGroupStore: currentGroupStore,
    );

    final AuthResult result = await api.login('honey', 'secret12');

    expect(result, isA<AuthenticatedSession>());
    expect(currentGroupStore.activeUserId, userA);
    expect(
      await currentGroupStore.load(),
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    );
    expect(sessionStore.refreshToken, 'refresh-new');
    expect(sessionStore.writeCount, 1);
    expect(requestCount, 4);
  });

  test('starter group failure leaves login uncommitted and account inactive',
      () async {
    final _MemoryGirlsSessionStore sessionStore = _MemoryGirlsSessionStore();
    final _MemoryCurrentGroupStore currentGroupStore =
        _MemoryCurrentGroupStore();
    int requestCount = 0;
    final MockClient client = MockClient((http.Request request) async {
      requestCount += 1;
      switch (requestCount) {
        case 1:
          return _jsonResponse(<String, Object?>{
            'state': 'authenticated',
            'access_token': 'access-new',
            'token_type': 'Bearer',
            'expires_in': 3600,
            'refresh_token': 'refresh-new',
          });
        case 2:
          return _meResponse(userA);
        case 3:
          return _groupsResponse(const <Map<String, Object?>>[]);
        case 4:
          return _jsonResponse(
            <String, Object?>{
              'error': 'temporary_failure',
              'message': 'group service unavailable',
            },
            statusCode: 503,
          );
        default:
          fail(
            'Unexpected request #$requestCount: '
            '${request.method} ${request.url}',
          );
      }
    });
    final HostedGirlsApi api = HostedGirlsApi(
      baseUri: baseUri,
      client: client,
      sessionStore: sessionStore,
      currentGroupStore: currentGroupStore,
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
    expect(currentGroupStore.activeUserId, isNull);
    expect(requestCount, 4);
  });

  test('logout preserves remembered group for the account', () async {
    final _MemoryGirlsSessionStore sessionStore =
        _MemoryGirlsSessionStore(refreshToken: 'refresh-saved');
    final _MemoryCurrentGroupStore currentGroupStore =
        _MemoryCurrentGroupStore(remembered: <String, String>{userA: groupA});
    await currentGroupStore.activateAccount(userA);
    final HostedGirlsApi api = HostedGirlsApi(
      baseUri: baseUri,
      client: MockClient((http.Request request) async {
        fail('Logout must not make a network request.');
      }),
      sessionStore: sessionStore,
      currentGroupStore: currentGroupStore,
    );

    await api.logout();

    expect(sessionStore.refreshToken, isNull);
    expect(sessionStore.clearCount, 1);
    expect(currentGroupStore.activeUserId, isNull);
    await currentGroupStore.activateAccount(userA);
    expect(await currentGroupStore.load(), groupA);
  });

  test('explicit invalid_refresh_token clears saved login', () async {
    final _MemoryGirlsSessionStore sessionStore = _MemoryGirlsSessionStore(
      refreshToken: 'refresh-expired',
    );
    final _MemoryCurrentGroupStore currentGroupStore =
        _MemoryCurrentGroupStore();
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
      sessionStore: sessionStore,
      currentGroupStore: currentGroupStore,
    );

    final AuthenticatedSession? session = await api.restoreSession();

    expect(session, isNull);
    expect(sessionStore.refreshToken, isNull);
    expect(sessionStore.clearCount, 1);
    expect(currentGroupStore.activeUserId, isNull);
  });

  test('transient refresh failure preserves saved login and propagates error',
      () async {
    final _MemoryGirlsSessionStore sessionStore = _MemoryGirlsSessionStore(
      refreshToken: 'refresh-keep-me',
    );
    final _MemoryCurrentGroupStore currentGroupStore =
        _MemoryCurrentGroupStore();
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
      sessionStore: sessionStore,
      currentGroupStore: currentGroupStore,
    );

    await expectLater(
      api.restoreSession(),
      throwsA(
        isA<ApiException>()
            .having((ApiException e) => e.statusCode, 'statusCode', 503)
            .having((ApiException e) => e.code, 'code', 'temporary_failure'),
      ),
    );

    expect(sessionStore.refreshToken, 'refresh-keep-me');
    expect(sessionStore.clearCount, 0);
    expect(currentGroupStore.activeUserId, isNull);
  });

  test('authenticated login without refresh_token fails closed', () async {
    final _MemoryGirlsSessionStore sessionStore = _MemoryGirlsSessionStore();
    final _MemoryCurrentGroupStore currentGroupStore =
        _MemoryCurrentGroupStore();
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
      sessionStore: sessionStore,
      currentGroupStore: currentGroupStore,
    );

    await expectLater(api.login('honey', 'secret12'), throwsFormatException);
    expect(sessionStore.writeCount, 0);
    expect(currentGroupStore.activeUserId, isNull);
  });
}

class _MemoryCurrentGroupStore
    implements GirlsCurrentGroupStore, GirlsCurrentGroupAccountScope {
  _MemoryCurrentGroupStore({Map<String, String>? remembered})
      : remembered = <String, String>{...?remembered};

  final Map<String, String> remembered;
  String? activeUserId;

  @override
  Future<void> activateAccount(String userId) async {
    activeUserId = userId;
  }

  @override
  Future<void> deactivateAccount() async {
    activeUserId = null;
  }

  String _requireActiveUserId() {
    final String? userId = activeUserId;
    if (userId == null) {
      throw StateError('No active test account.');
    }
    return userId;
  }

  @override
  Future<String?> load() async => remembered[_requireActiveUserId()];

  @override
  Future<void> save(String groupId) async {
    remembered[_requireActiveUserId()] = groupId;
  }

  @override
  Future<void> clear() async {
    remembered.remove(_requireActiveUserId());
  }
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

Map<String, Object?> _group(String groupId, String name) {
  return <String, Object?>{
    'group_id': groupId,
    'name': name,
    'role': 'owner',
    'status': 'active',
  };
}

http.Response _groupsResponse(List<Map<String, Object?>> groups) {
  return _jsonResponse(<String, Object?>{'groups': groups});
}

http.Response _meResponse(String userId) {
  return _jsonResponse(<String, Object?>{
    'user': <String, Object?>{
      'user_id': userId,
      'login_id': 'honey',
      'role': 'user',
      'status': 'active',
    },
    'groups': <Object?>[],
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
