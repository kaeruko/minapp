import 'package:flutter/foundation.dart';

import 'endpoint_validation.dart';

Uri? resolveCreatorPortalBaseUriForPlatform({
  required String rawBaseUrl,
  required TargetPlatform targetPlatform,
}) {
  final Uri? configuredBaseUri = rawBaseUrl.isEmpty
      ? null
      : validatePublicHttpsBaseUri(
          Uri.parse(rawBaseUrl),
          argumentName: 'MINAPP_CREATOR_PORTAL_BASE_URL',
        );

  if (targetPlatform != TargetPlatform.android) return null;
  return configuredBaseUri;
}
