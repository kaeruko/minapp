import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/girls_shop_api.dart';

String _repeat(String value, int count) => List<String>.filled(count, value).join();

void main() {
  final String appId = _repeat('a', 32);
  final String ownerId = _repeat('c', 32);
  final String sha256 = _repeat('d', 64);

  test('listApps reads the cross-group Girls shop contract', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url, Uri.parse('https://girls-api.example.com/shop/apps'));
      expect(request.headers['authorization'], 'Bearer token');
      return http.Response(
        jsonEncode(<String, Object?>{
          'apps': <Object?>[
            <String, Object?>{
              'app_id': appId,
              'version': '3',
              'title': '放課後ねこ',
              'owner_user_id': ownerId,
              'owner_display_name': 'creator',
              'published_at': '2026-09-13T02:00:00Z',
              'sha256': sha256,
            },
          ],
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final GirlsShopApi api = GirlsShopApi(
      baseUri: Uri.parse('https://girls-api.example.com'),
      client: client,
    );
    addTearDown(api.close);

    final List<GirlsShopApp> apps = await api.listApps('token');
    expect(apps, hasLength(1));
    expect(apps.single.appId, appId);
    expect(apps.single.version, '3');
    expect(apps.single.ownerDisplayName, 'creator');
  });

  test('createLaunch sends exact version and requires runtime token', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(
        request.url,
        Uri.parse('https://girls-api.example.com/shop/apps/$appId/launch'),
      );
      expect(jsonDecode(request.body), <String, Object?>{'version': '3'});
      return http.Response(
        jsonEncode(<String, Object?>{
          'url': 'https://girls-api.example.com/shop/content/token/index.html',
          'runtime_token': _repeat('r', 40),
          'expires_in': 600,
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final GirlsShopApi api = GirlsShopApi(
      baseUri: Uri.parse('https://girls-api.example.com'),
      client: client,
    );
    addTearDown(api.close);
    final GirlsShopApp app = GirlsShopApp(
      appId: appId,
      version: '3',
      title: '作品',
      ownerUserId: ownerId,
      ownerDisplayName: 'creator',
      publishedAt: DateTime.utc(2026, 9, 13),
      sha256: sha256,
    );

    final GirlsShopLaunchGrant grant = await api.createLaunch(
      accessToken: 'token',
      app: app,
    );
    expect(grant.runtimeToken, _repeat('r', 40));
    expect(grant.expiresIn, 600);
  });

  test('createDownload fails closed when sha256 differs from listing', () async {
    final MockClient client = MockClient((http.Request request) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'url': 'https://download.example.com/source.zip?sig=x',
          'filename': '$appId.zip',
          'sha256': _repeat('e', 64),
          'expires_in': 600,
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final GirlsShopApi api = GirlsShopApi(
      baseUri: Uri.parse('https://girls-api.example.com'),
      client: client,
    );
    addTearDown(api.close);
    final GirlsShopApp app = GirlsShopApp(
      appId: appId,
      version: '3',
      title: '作品',
      ownerUserId: ownerId,
      ownerDisplayName: 'creator',
      publishedAt: DateTime.utc(2026, 9, 13),
      sha256: sha256,
    );

    expect(
      () => api.createDownload(accessToken: 'token', app: app),
      throwsA(isA<FormatException>()),
    );
  });

  test('setVisibility sends app-level Girls shop state', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'PUT');
      expect(
        request.url,
        Uri.parse('https://girls-api.example.com/apps/$appId/shop-visibility'),
      );
      expect(
        jsonDecode(request.body),
        <String, Object?>{'visibility': 'listed'},
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'app_id': appId,
          'shop_visibility': 'listed',
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final GirlsShopApi api = GirlsShopApi(
      baseUri: Uri.parse('https://girls-api.example.com'),
      client: client,
    );
    addTearDown(api.close);

    await api.setVisibility(
      accessToken: 'token',
      appId: appId,
      listed: true,
    );
  });

  test('listApps rejects unexpected fields instead of ignoring them', () async {
    final MockClient client = MockClient((http.Request request) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'apps': <Object?>[
            <String, Object?>{
              'app_id': appId,
              'version': '3',
              'title': '作品',
              'owner_user_id': ownerId,
              'owner_display_name': 'creator',
              'published_at': '2026-09-13T02:00:00Z',
              'sha256': sha256,
              'group_id': _repeat('f', 32),
            },
          ],
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final GirlsShopApi api = GirlsShopApi(
      baseUri: Uri.parse('https://girls-api.example.com'),
      client: client,
    );
    addTearDown(api.close);

    expect(() => api.listApps('token'), throwsA(isA<FormatException>()));
  });
}
