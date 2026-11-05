import '../api.dart';
import '../hosted_shop_api.dart';

/// Checks a freshly fetched catalog entry against the one the user selected.
/// A publication change is never silently accepted as a different launch.
void requireCurrentKoboShopVersion(
  HostedShopApp selected,
  List<HostedShopApp> freshApps,
) {
  final List<HostedShopApp> matches = freshApps
      .where((HostedShopApp app) => app.appId == selected.appId)
      .toList(growable: false);
  if (matches.isEmpty) {
    throw const ApiException(
      statusCode: 404,
      code: 'shop_app_not_found',
      message: 'この作品は現在ショップにありません。更新された一覧を確認してください。',
    );
  }
  if (matches.length != 1) {
    throw StateError('Shop catalog returned duplicate app identities.');
  }
  final HostedShopApp current = matches.single;
  if (current.version != selected.version ||
      current.sha256 != selected.sha256) {
    throw const ApiException(
      statusCode: 409,
      code: 'shop_version_stale',
      message: '作品が更新されました。一覧は最新になったので、もう一度「遊んでみる」を押してください。',
    );
  }
}
