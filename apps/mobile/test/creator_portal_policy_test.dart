import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/creator_portal_policy.dart';

void main() {
  test('creator portal is available on Android when configured', () {
    expect(
      resolveCreatorPortalBaseUriForPlatform(
        rawBaseUrl: 'https://minapp.cloxs.jp',
        targetPlatform: TargetPlatform.android,
      ),
      Uri.parse('https://minapp.cloxs.jp'),
    );
  });

  test('creator portal is unavailable on iOS even when configured', () {
    expect(
      resolveCreatorPortalBaseUriForPlatform(
        rawBaseUrl: 'https://minapp.cloxs.jp',
        targetPlatform: TargetPlatform.iOS,
      ),
      isNull,
    );
  });

  test('missing creator portal remains unavailable', () {
    expect(
      resolveCreatorPortalBaseUriForPlatform(
        rawBaseUrl: '',
        targetPlatform: TargetPlatform.android,
      ),
      isNull,
    );
  });

  test('invalid configured creator portal still fails fast on iOS', () {
    expect(
      () => resolveCreatorPortalBaseUriForPlatform(
        rawBaseUrl: 'http://minapp.cloxs.jp',
        targetPlatform: TargetPlatform.iOS,
      ),
      throwsArgumentError,
    );
  });
}
