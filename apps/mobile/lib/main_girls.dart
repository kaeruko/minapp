import 'package:flutter/material.dart';

import 'endpoint_validation.dart';
import 'girls/girls_app.dart';
import 'girls/hosted_girls_api.dart';

void main() {
  const String rawHostedApiBaseUrl = String.fromEnvironment(
    'MINAPP_HOSTED_API_BASE_URL',
  );
  if (rawHostedApiBaseUrl.isEmpty) {
    throw StateError(
      'MINAPP_HOSTED_API_BASE_URL is required for MinApp Girls. '
      'Run with --dart-define=MINAPP_HOSTED_API_BASE_URL=https://...',
    );
  }

  final Uri hostedApiBaseUri = validatePublicHttpsBaseUri(
    Uri.parse(rawHostedApiBaseUrl),
    argumentName: 'MINAPP_HOSTED_API_BASE_URL',
  );

  runApp(
    GirlsApp(
      api: HostedGirlsApi(baseUri: hostedApiBaseUri),
    ),
  );
}
