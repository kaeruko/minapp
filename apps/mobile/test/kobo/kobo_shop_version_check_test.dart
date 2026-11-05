import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/api.dart';
import 'package:minapp_mobile/hosted_shop_api.dart';
import 'package:minapp_mobile/kobo/kobo_shop_version_check.dart';

const String _appId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _ownerId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String _hash2 = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const String _hash3 = 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';

HostedShopApp _app({String version = '2', String hash = _hash2}) =>
    HostedShopApp(
      appId: _appId,
      version: version,
      title: '町中華メモ',
      ownerUserId: _ownerId,
      ownerDisplayName: 'テスト作者',
      publishedAt: DateTime.utc(2026, 11, 5),
      sha256: hash,
    );

void main() {
  test('freshly listed unchanged app is launchable', () {
    expect(() => requireCurrentKoboShopVersion(_app(), <HostedShopApp>[_app()]),
        returnsNormally);
  });

  test('an old published version is rejected until the user selects it again', () {
    expect(
      () => requireCurrentKoboShopVersion(_app(), <HostedShopApp>[
        _app(version: '3', hash: _hash3),
      ]),
      throwsA(isA<ApiException>()
          .having((ApiException e) => e.statusCode, 'statusCode', 409)
          .having((ApiException e) => e.code, 'code', 'shop_version_stale')),
    );
  });

  test('unexpected SHA for the same version also refuses launch', () {
    expect(
      () => requireCurrentKoboShopVersion(_app(),
          <HostedShopApp>[_app(hash: _hash3)]),
      throwsA(isA<ApiException>().having(
          (ApiException e) => e.code, 'code', 'shop_version_stale')),
    );
  });

  test('missing listing fails without launching another app', () {
    expect(
      () => requireCurrentKoboShopVersion(_app(), const <HostedShopApp>[]),
      throwsA(isA<ApiException>().having(
          (ApiException e) => e.code, 'code', 'shop_app_not_found')),
    );
  });

  test('duplicate listing identity is rejected rather than choosing first', () {
    expect(
      () => requireCurrentKoboShopVersion(
          _app(), <HostedShopApp>[_app(), _app()]),
      throwsStateError,
    );
  });
}
