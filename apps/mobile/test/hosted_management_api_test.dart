import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/hosted_app_management_api.dart';
import 'package:minapp_mobile/hosted_group_management_api.dart';

const String _token = 'access-token';
const String _groupId = '11111111111111111111111111111111';
const String _appId = '22222222222222222222222222222222';
const String _userId = '33333333333333333333333333333333';

http.Response _json(int statusCode, Object body) => http.Response(
      jsonEncode(body),
      statusCode,
      headers: const <String, String>{'content-type': 'application/json'},
    );

Map<String, Object?> _managedAppJson() => <String, Object?>{
      'app_id': _appId,
      'group_id': _groupId,
      'title': 'テストアプリ',
      'source_kind': 'upload',
      'created_at': '2026-09-07T00:00:00Z',
      'published_version': 2,
      'owner_user_id': _userId,
      'source_revision': 3,
      'source_updated_at': '2026-09-07T01:00:00Z',
      'published_at': '2026-09-07T02:00:00Z',
      'visibility': 'visible',
      'group_name': 'テストグループ',
      'stats': <String, Object?>{
        'total_plays': 8,
        'unique_users': 4,
        'monthly_plays': 5,
      },
    };

void main() {
  test('shared app management lists the authenticated user apps', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/hosted/my/apps');
      expect(request.headers['authorization'], 'Bearer $_token');
      return _json(200, <String, Object?>{
        'apps': <Object?>[_managedAppJson()],
      });
    });
    final HostedAppManagementApi api = HostedAppManagementApi(
      baseUri: Uri.parse('https://hosted.example'),
      client: client,
    );

    final List<ManagedHostedApp> apps = await api.listApps(_token);

    expect(apps, hasLength(1));
    expect(apps.single.app.appId, _appId);
    expect(apps.single.app.ownerUserId, _userId);
    expect(apps.single.groupName, 'テストグループ');
    expect(apps.single.stats.totalPlays, 8);
  });

  test('ownership transfer keeps the requested group and user scope', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/hosted/groups/$_groupId/owner');
      expect(request.headers['authorization'], 'Bearer $_token');
      expect(jsonDecode(request.body), <String, Object?>{'user_id': _userId});
      return _json(200, <String, Object?>{
        'group_id': _groupId,
        'owner_user_id': _userId,
      });
    });
    final HostedGroupManagementApi api = HostedGroupManagementApi(
      baseUri: Uri.parse('https://hosted.example'),
      client: client,
    );

    final HostedOwnershipTransferResult result = await api.transferOwnership(
      accessToken: _token,
      groupId: _groupId,
      newOwnerUserId: _userId,
    );

    expect(result.groupId, _groupId);
    expect(result.ownerUserId, _userId);
  });

  test('member removal requires an exact 204 response', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'DELETE');
      expect(
        request.url.path,
        '/hosted/groups/$_groupId/members/$_userId',
      );
      expect(request.headers['authorization'], 'Bearer $_token');
      return http.Response('', 204);
    });
    final HostedGroupManagementApi api = HostedGroupManagementApi(
      baseUri: Uri.parse('https://hosted.example'),
      client: client,
    );

    await api.removeMember(
      accessToken: _token,
      groupId: _groupId,
      userId: _userId,
    );
  });

  test('ownership response fails closed when scope is changed', () async {
    final MockClient client = MockClient((http.Request request) async {
      return _json(200, <String, Object?>{
        'group_id': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'owner_user_id': _userId,
      });
    });
    final HostedGroupManagementApi api = HostedGroupManagementApi(
      baseUri: Uri.parse('https://hosted.example'),
      client: client,
    );

    expect(
      () => api.transferOwnership(
        accessToken: _token,
        groupId: _groupId,
        newOwnerUserId: _userId,
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
