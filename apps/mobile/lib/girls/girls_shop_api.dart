import 'package:http/http.dart' as http;

import '../hosted_shop_api.dart';

export '../hosted_shop_api.dart';

typedef GirlsShopApp = HostedShopApp;
typedef GirlsShopLaunchGrant = HostedShopLaunchGrant;
typedef GirlsShopDownloadGrant = HostedShopDownloadGrant;

/// Backwards-compatible Girls name for the edition-neutral shop API.
class GirlsShopApi extends HostedShopApi {
  GirlsShopApi({required super.baseUri, http.Client? client})
      : super(client: client);
}
