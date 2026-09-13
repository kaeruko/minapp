import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/shop_api.dart';

String _repeat(String value, int count) => List<String>.filled(count, value).join();

void main() {
  test('listApps parses classic classroom shop payload', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url, Uri.parse('https://api.example.com/shop/apps'));
      expect(request.headers['authorization'], 'Bearer token');
      return http.Response(
        jsonEncode(<String, Object?>{
          'apps': <Object?>[
            <String, Object?>{
              'app_id': _repeat('a', 32),
              'version_id': _repeat('b', 32),
              'owner_user_id': _repeat('c', 32),
              'owner_display_name': '作者',
              'title': '作品A',
              'reviewed_at': '2026-09-13T01:00:00Z',
              'sha256': _repeat('d', 64),
            },
          ],
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final ShopApiClient api = ShopApiClient(
      baseUri: Uri.parse('https://api.example.com'),
      client: client,
    );
    addTearDown(api.close);

    final List<ShopApp> apps = await api.listApps('token');
    expect(apps, hasLength(1));
    expect(apps.single.version, _repeat('b', 32));
    expect(apps.single.ownerDisplayName, '作者');
  });

  test('listApps parses Hosted Girls shop payload with same model', () async {
    final MockClient client = MockClient((http.Request request) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'apps': <Object?>[
            <String, Object?>{
              'app_id': _repeat('a', 32),
              'version': '3',
              'owner_user_id': _repeat('c', 32),
              'owner_display_name': 'girls-author',
              'title': '作品B',
              'published_at': '2026-09-13T02:00:00Z',
              'sha256': _repeat('d', 64),
            },
          ],
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final ShopApiClient api = ShopApiClient(
      baseUri: Uri.parse('https://girls-api.example.com'),
      client: client,
    );
    addTearDown(api.close);

    final List<ShopApp> apps = await api.listApps('token');
    expect(apps.single.version, '3');
    expect(apps.single.title, '作品B');
  });

  test('createLaunch posts exact selected version token', () async {
    final String appId = _repeat('a', 32);
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(
        request.url,
        Uri.parse('https://api.example.com/shop/apps/$appId/launch'),
      );
      expect(jsonDecode(request.body), <String, Object?>{'version': '7'});
      return http.Response(
        jsonEncode(<String, Object?>{
          'url': 'https://api.example.com/shop/content/token/index.html',
          'expires_in': 600,
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final ShopApiClient api = ShopApiClient(
      baseUri: Uri.parse('https://api.example.com'),
      client: client,
    );
    addTearDown(api.close);
    final ShopApp app = ShopApp(
      appId: appId,
      version: '7',
      title: '作品',
      ownerUserId: _repeat('c', 32),
      ownerDisplayName: '作者',
      publishedAt: DateTime.utc(2026, 9, 13),
      sha256: _repeat('d', 64),
    );

    final ShopLaunchGrant grant = await api.createLaunch(
      accessToken: 'token',
      app: app,
    );
    expect(grant.expiresIn, 600);
  });

  test('createDownload fails when server sha differs from listing', () async {
    final MockClient client = MockClient((http.Request request) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'url': 'https://download.example.com/app.zip?sig=x',
          'filename': 'app.zip',
          'sha256': _repeat('e', 64),
          'expires_in': 600,
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final ShopApiClient api = ShopApiClient(
      baseUri: Uri.parse('https://api.example.com'),
      client: client,
    );
    addTearDown(api.close);
    final ShopApp app = ShopApp(
      appId: _repeat('a', 32),
      version: _repeat('b', 32),
      title: '作品',
      ownerUserId: _repeat('c', 32),
      ownerDisplayName: '作者',
      publishedAt: DateTime.utc(2026, 9, 13),
      sha256: _repeat('d', 64),
    );

    expect(
      () => api.createDownload(accessToken: 'token', app: app),
      throwsA(isA<FormatException>()),
    );
  });

  test('listApps rejects conflicting version fields', () async {
    final MockClient client = MockClient((http.Request request) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'apps': <Object?>[
            <String, Object?>{
              'app_id': _repeat('a', 32),
              'version': '3',
              'version_id': _repeat('b', 32),
              'owner_user_id': _repeat('c', 32),
              'owner_display_name': '作者',
              'title': '壊れた作品',
              'published_at': '2026-09-13T02:00:00Z',
              'sha256': _repeat('d', 64),
            },
          ],
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final ShopApiClient api = ShopApiClient(
      baseUri: Uri.parse('https://api.example.com'),
      client: client,
    );
    addTearDown(api.close);

    expect(() => api.listApps('token'), throwsA(isA<FormatException>()));
  });
}
