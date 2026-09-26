import 'package:http/http.dart' as http;

import 'endpoint_validation.dart';
import 'hosted_endpoint_source.dart';

const String minAppGirlsHostedGoogleDriveFileId = minAppHostedGoogleDriveFileId;
const Duration minAppGirlsHostedFetchTimeout = minAppHostedFetchTimeout;

const bool minAppGirlsDemoFast = bool.fromEnvironment(
  'MINAPP_DEMO_FAST',
  defaultValue: false,
);
const String minAppGirlsDemoHostedBaseUri = String.fromEnvironment(
  'MINAPP_HOSTED_BASE_URI',
);

Future<Uri> loadGirlsHostedBaseUri({
  http.Client? client,
  DateTime? now,
}) {
  if (!minAppGirlsDemoFast) {
    return loadGirlsHostedBaseUriFromGoogleDrive(client: client, now: now);
  }

  if (minAppGirlsDemoHostedBaseUri.isEmpty) {
    throw StateError(
      'MINAPP_DEMO_FAST=true requires a non-empty '
      'MINAPP_HOSTED_BASE_URI dart-define.',
    );
  }
  final Uri? parsed = Uri.tryParse(minAppGirlsDemoHostedBaseUri);
  if (parsed == null) {
    throw FormatException(
      'MINAPP_HOSTED_BASE_URI is not a valid URI.',
      minAppGirlsDemoHostedBaseUri,
    );
  }
  return Future<Uri>.value(
    validatePublicHttpsBaseUri(
      parsed,
      argumentName: 'MINAPP_HOSTED_BASE_URI',
    ),
  );
}

Future<Uri> loadGirlsHostedBaseUriFromGoogleDrive({
  http.Client? client,
  DateTime? now,
}) {
  return loadHostedBaseUriFromGoogleDrive(client: client, now: now);
}
