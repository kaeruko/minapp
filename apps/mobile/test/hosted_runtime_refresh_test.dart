import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/api.dart';
import 'package:minapp_mobile/hosted_runtime_bridge.dart';

const String _groupId = '22222222222222222222222222222222';
const String _appId = '33333333333333333333333333333333';
const String _firstRuntimeToken =
    'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
const String _secondRuntimeToken =
    'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD';
const String _firstContentToken =
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const String _secondContentToken =
    'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';

http.Response _jsonResponse(Map<String, Object?> body, int statusCode) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

Map<String, Object?> _launchResponse({
  required String contentToken,
  required String runtimeToken,
}) {
  return <String, Object?>{
    'content_path': '/hosted/content/$contentToken/index.html',
    'content_expires_in': 600,
    'runtime_token': runtimeToken,
    'runtime_expires_in': 600,
    'published_version': 1,
  };
}

void main() {
  test('refreshes an expired registered Runtime session once and retries the same operation', () async {
    int launchCount = 0;
    final List<String> runtimePaths = <String>[];
    final MockClient client = MockClient((http.Request request) async {
      if (request.url.path ==
          '/hosted/groups/$_groupId/apps/$_appId/launch-session') {
        launchCount += 1;
        expect(request.method, 'POST');
        expect(request.headers['Authorization'], 'Bearer parent-cognito-token');
        expect(jsonDecode(request.body), <String, Object?>{});
        if (launchCount == 1) {
          return _jsonResponse(
            _launchResponse(
              contentToken: _firstContentToken,
              runtimeToken: _firstRuntimeToken,
            ),
            201,
          );
        }
        if (launchCount == 2) {
          return _jsonResponse(
            _launchResponse(
              contentToken: _secondContentToken,
              runtimeToken: _secondRuntimeToken,
            ),
            201,
          );
        }
        fail('Runtime refresh created more than one replacement launch session.');
      }

      runtimePaths.add(request.url.path);
      expect(request.headers.containsKey('Authorization'), isFalse);
      if (request.url.path ==
          '/hosted/runtime/$_firstRuntimeToken/user-state/progress') {
        return _jsonResponse(
          <String, Object?>{
            'error': 'runtime_session_not_found',
            'message': 'Runtime session is invalid or expired.',
          },
          404,
        );
      }
      if (request.url.path ==
          '/hosted/runtime/$_secondRuntimeToken/user-state/progress') {
        return _jsonResponse(
          <String, Object?>{
            'key': 'progress',
            'value': <String, Object?>{'scene': 'scene_007'},
            'updated_at': '2026-09-06T09:00:00Z',
          },
          200,
        );
      }
      if (request.url.path ==
          '/hosted/runtime/$_secondRuntimeToken/state/shared') {
        return _jsonResponse(
          <String, Object?>{
            'key': 'shared',
            'value': 4,
            'updated_at': '2026-09-06T09:00:01Z',
          },
          200,
        );
      }
      fail('Unexpected request: ${request.method} ${request.url}');
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
    expect(launch.runtimeToken, _firstRuntimeToken);

    final Object? progress = await api.getUserState(
      launch.runtimeToken,
      'progress',
    );
    expect(progress, <String, Object?>{'scene': 'scene_007'});

    final Object? shared = await api.getState(launch.runtimeToken, 'shared');
    expect(shared, 4);
    expect(launchCount, 2);
    expect(runtimePaths, <String>[
      '/hosted/runtime/$_firstRuntimeToken/user-state/progress',
      '/hosted/runtime/$_secondRuntimeToken/user-state/progress',
      '/hosted/runtime/$_secondRuntimeToken/state/shared',
    ]);
  });

  test('does not perform a second automatic refresh when the retried operation also reports expiry', () async {
    int launchCount = 0;
    int runtimeRequestCount = 0;
    final MockClient client = MockClient((http.Request request) async {
      if (request.url.path ==
          '/hosted/groups/$_groupId/apps/$_appId/launch-session') {
        launchCount += 1;
        return _jsonResponse(
          _launchResponse(
            contentToken:
                launchCount == 1 ? _firstContentToken : _secondContentToken,
            runtimeToken:
                launchCount == 1 ? _firstRuntimeToken : _secondRuntimeToken,
          ),
          201,
        );
      }
      runtimeRequestCount += 1;
      return _jsonResponse(
        <String, Object?>{
          'error': 'runtime_session_not_found',
          'message': 'Runtime session is invalid or expired.',
        },
        404,
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

    await expectLater(
      api.getUserState(launch.runtimeToken, 'progress'),
      throwsA(
        isA<ApiException>()
            .having((ApiException error) => error.statusCode, 'statusCode', 404)
            .having(
              (ApiException error) => error.code,
              'code',
              'runtime_session_not_found',
            ),
      ),
    );
    expect(launchCount, 2);
    expect(runtimeRequestCount, 2);
  });

  test('preserves the expiry error and refresh failure when replacement launch fails', () async {
    int launchCount = 0;
    final MockClient client = MockClient((http.Request request) async {
      if (request.url.path ==
          '/hosted/groups/$_groupId/apps/$_appId/launch-session') {
        launchCount += 1;
        if (launchCount == 1) {
          return _jsonResponse(
            _launchResponse(
              contentToken: _firstContentToken,
              runtimeToken: _firstRuntimeToken,
            ),
            201,
          );
        }
        return _jsonResponse(
          <String, Object?>{
            'error': 'unauthorized',
            'message': 'Parent session is no longer authorized.',
          },
          401,
        );
      }
      return _jsonResponse(
        <String, Object?>{
          'error': 'runtime_session_not_found',
          'message': 'Runtime session is invalid or expired.',
        },
        404,
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

    await expectLater(
      api.getState(launch.runtimeToken, 'shared'),
      throwsA(
        isA<HostedRuntimeRefreshException>()
            .having(
              (HostedRuntimeRefreshException error) =>
                  error.expiredSessionError.code,
              'expiredSessionError.code',
              'runtime_session_not_found',
            )
            .having(
              (HostedRuntimeRefreshException error) => error.refreshError,
              'refreshError',
              isA<ApiException>()
                  .having((ApiException error) => error.statusCode, 'statusCode', 401)
                  .having((ApiException error) => error.code, 'code', 'unauthorized'),
            )
            .having(
              (HostedRuntimeRefreshException error) => error.refreshStackTrace,
              'refreshStackTrace',
              isA<StackTrace>(),
            ),
      ),
    );
    expect(launchCount, 2);
  });
}
