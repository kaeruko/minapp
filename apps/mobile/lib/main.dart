import 'package:flutter/material.dart';

import 'api.dart';
import 'session_app.dart';

void main() {
  const String rawApiBaseUrl = String.fromEnvironment('MINAPP_API_BASE_URL');
  if (rawApiBaseUrl.isEmpty) {
    throw StateError(
      'MINAPP_API_BASE_URL is required. Run with '
      '--dart-define=MINAPP_API_BASE_URL=https://...',
    );
  }
  final Uri baseUri = Uri.parse(rawApiBaseUrl);
  runApp(MinApp(api: MinAppApiClient(baseUri: baseUri)));
}
