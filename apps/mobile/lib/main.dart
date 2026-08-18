import 'package:flutter/material.dart';

import 'api.dart';
import 'directory.dart';
import 'endpoint_validation.dart';
import 'session_app.dart';
import 'tenant_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  const String rawDirectoryBaseUrl = String.fromEnvironment(
    'MINAPP_DIRECTORY_BASE_URL',
  );
  if (rawDirectoryBaseUrl.isEmpty) {
    throw StateError(
      'MINAPP_DIRECTORY_BASE_URL is required. Run with '
      '--dart-define=MINAPP_DIRECTORY_BASE_URL=https://...',
    );
  }

  final Uri directoryBaseUri = validatePublicHttpsBaseUri(
    Uri.parse(rawDirectoryBaseUrl),
    argumentName: 'MINAPP_DIRECTORY_BASE_URL',
  );

  const String rawJoinBaseUrl = String.fromEnvironment(
    'MINAPP_JOIN_BASE_URL',
  );
  final Uri? joinBaseUri = rawJoinBaseUrl.isEmpty
      ? null
      : validatePublicHttpsBaseUri(
          Uri.parse(rawJoinBaseUrl),
          argumentName: 'MINAPP_JOIN_BASE_URL',
        );

  const String rawCreatorPortalBaseUrl = String.fromEnvironment(
    'MINAPP_CREATOR_PORTAL_BASE_URL',
  );
  final Uri? creatorPortalBaseUri = rawCreatorPortalBaseUrl.isEmpty
      ? null
      : validatePublicHttpsBaseUri(
          Uri.parse(rawCreatorPortalBaseUrl),
          argumentName: 'MINAPP_CREATOR_PORTAL_BASE_URL',
        );

  runApp(
    MinApp(
      directory: MinAppDirectoryClient(baseUri: directoryBaseUri),
      tenantStore: SharedPreferencesTenantStore(),
      apiFactory: (Uri baseUri) => MinAppApiClient(baseUri: baseUri),
      officialJoinBaseUri: joinBaseUri,
      creatorPortalBaseUri: creatorPortalBaseUri,
    ),
  );
}
