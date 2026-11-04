import 'package:http/http.dart' as http;

import 'endpoint_validation.dart';
import 'hosted_endpoint_source.dart';

const String minAppKoboHostedGoogleDriveFileId = String.fromEnvironment(
  'MINAPP_KOBO_HOSTED_ENDPOINT_FILE_ID',
);
const String minAppKoboHostedBaseUri = String.fromEnvironment(
  'MINAPP_KOBO_HOSTED_BASE_URI',
);

/// Loads the Kobo deployment without ever falling back to the Girls endpoint.
Future<Uri> loadKoboHostedBaseUri({
  http.Client? client,
  DateTime? now,
  String directBaseUri = minAppKoboHostedBaseUri,
  String googleDriveFileId = minAppKoboHostedGoogleDriveFileId,
}) {
  if (directBaseUri.isNotEmpty) {
    final Uri? parsed = Uri.tryParse(directBaseUri);
    if (parsed == null) {
      throw FormatException(
        'MINAPP_KOBO_HOSTED_BASE_URI is not a valid URI.',
        directBaseUri,
      );
    }
    return Future<Uri>.value(
      validatePublicHttpsBaseUri(
        parsed,
        argumentName: 'MINAPP_KOBO_HOSTED_BASE_URI',
      ),
    );
  }
  if (googleDriveFileId.isEmpty) {
    throw StateError(
      'Kobo Hosted endpoint is not configured. Set '
      'MINAPP_KOBO_HOSTED_BASE_URI or '
      'MINAPP_KOBO_HOSTED_ENDPOINT_FILE_ID.',
    );
  }
  return loadHostedBaseUriFromGoogleDrive(
    fileId: googleDriveFileId,
    client: client,
    now: now,
  );
}
