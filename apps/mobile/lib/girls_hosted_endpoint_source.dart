import 'package:http/http.dart' as http;

import 'hosted_endpoint_source.dart';

const String minAppGirlsHostedGoogleDriveFileId = minAppHostedGoogleDriveFileId;
const Duration minAppGirlsHostedFetchTimeout = minAppHostedFetchTimeout;

Future<Uri> loadGirlsHostedBaseUriFromGoogleDrive({
  http.Client? client,
  DateTime? now,
}) {
  return loadHostedBaseUriFromGoogleDrive(client: client, now: now);
}
