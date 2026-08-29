import 'package:http/http.dart' as http;

import 'endpoint_validation.dart';

const String minAppDirectoryGoogleDriveFileId =
    '1mNyZWD5utMMkBhvGKhWPloTVOoE05W9u';
const Duration minAppDirectoryConfigTimeout = Duration(seconds: 12);

Future<Uri> resolveDirectoryBaseUri({
  String explicitBaseUrl = '',
  http.Client? client,
  DateTime Function()? now,
}) async {
  if (explicitBaseUrl.isNotEmpty) {
    return validatePublicHttpsBaseUri(
      Uri.parse(explicitBaseUrl),
      argumentName: 'MINAPP_DIRECTORY_BASE_URL',
    );
  }

  final bool ownsClient = client == null;
  final http.Client resolvedClient = client ?? http.Client();
  try {
    final DateTime timestamp = (now ?? DateTime.now)();
    final Uri configUri = Uri.https(
      'drive.google.com',
      '/uc',
      <String, String>{
        'export': 'download',
        'id': minAppDirectoryGoogleDriveFileId,
        't': timestamp.millisecondsSinceEpoch.toString(),
      },
    );

    final http.Response response = await resolvedClient
        .get(
          configUri,
          headers: const <String, String>{'Accept': 'text/plain'},
        )
        .timeout(minAppDirectoryConfigTimeout);

    if (response.statusCode != 200) {
      throw StateError(
        'Google Drive Directory config returned HTTP ${response.statusCode}.',
      );
    }

    final List<String> nonEmptyLines = response.body
        .split(RegExp(r'\r?\n'))
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .toList(growable: false);

    if (nonEmptyLines.length != 1) {
      throw const FormatException(
        'Google Drive Directory config must contain exactly one non-empty line.',
      );
    }

    return validatePublicHttpsBaseUri(
      Uri.parse(nonEmptyLines.single),
      argumentName: 'Google Drive Directory API base URL',
    );
  } finally {
    if (ownsClient) {
      resolvedClient.close();
    }
  }
}
