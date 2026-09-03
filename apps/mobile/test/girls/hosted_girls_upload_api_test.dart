import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/hosted_girls_upload_api.dart';

void main() {
  test('createFromZip sends raw application/zip with exact title query', () async {
    final String groupId = '2' * 32;
    final String appId = '3' * 32;
    final Uint8List zip = Uint8List.fromList(<int>[0x50, 0x4b, 1, 2, 3]);
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/hosted/groups/$groupId/apps/upload');
      expect(request.url.queryParameters, <String, String>{'title': '放課後アプリ'});
      expect(request.headers['content-type'], 'application/zip');
      expect(request.headers['authorization'], 'Bearer token');
      expect(request.bodyBytes, zip);
      return http.Response(
        jsonEncode(<String, Object?>{
          'app_id': appId,
          'group_id': groupId,
          'title': '放課後アプリ',
          'source_kind': 'upload',
          'created_at': '2026-09-03T00:00:00Z',
          'source_revision': 1,
          'editable': true,
        }),
        201,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final HostedGirlsUploadApi api = HostedGirlsUploadApi(
      baseUri: Uri.parse('https://example.test/'),
      client: client,
    );

    final app = await api.createFromZip(
      accessToken: 'token',
      groupId: groupId,
      title: '放課後アプリ',
      zipBytes: zip,
    );

    expect(app.appId, appId);
    expect(app.sourceKind, 'upload');
  });

  test('publish sends exact source revision', () async {
    final String groupId = '2' * 32;
    final String appId = '3' * 32;
    final MockClient client = MockClient((http.Request request) async {
      expect(
        request.url.path,
        '/hosted/groups/$groupId/apps/$appId/publish',
      );
      expect(jsonDecode(request.body), <String, Object?>{'revision': 1});
      return http.Response(
        jsonEncode(<String, Object?>{
          'app_id': appId,
          'group_id': groupId,
          'published_version': 1,
          'source_revision': 1,
          'sha256': 'abc',
          'files': <String>['index.html'],
          'published_at': '2026-09-03T00:00:00Z',
        }),
        201,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final HostedGirlsUploadApi api = HostedGirlsUploadApi(
      baseUri: Uri.parse('https://example.test/'),
      client: client,
    );

    final int version = await api.publish(
      accessToken: 'token',
      groupId: groupId,
      appId: appId,
      revision: 1,
    );

    expect(version, 1);
  });

  test('createFromZip rejects files larger than server 2MB limit', () async {
    final HostedGirlsUploadApi api = HostedGirlsUploadApi(
      baseUri: Uri.parse('https://example.test/'),
      client: MockClient((_) async => throw StateError('must not send')),
    );

    expect(
      () => api.createFromZip(
        accessToken: 'token',
        groupId: '2' * 32,
        title: 'too large',
        zipBytes: Uint8List(maxGirlsZipUploadBytes + 1),
      ),
      throwsArgumentError,
    );
  });
}
