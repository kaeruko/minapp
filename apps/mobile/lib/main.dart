import 'package:flutter/material.dart';

import 'api.dart';
import 'directory.dart';
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

  final Uri directoryBaseUri = Uri.parse(rawDirectoryBaseUrl);
  runApp(
    MinApp(
      directory: MinAppDirectoryClient(baseUri: directoryBaseUri),
      tenantStore: SharedPreferencesTenantStore(),
      apiFactory: (Uri baseUri) => MinAppApiClient(baseUri: baseUri),
    ),
  );
}
