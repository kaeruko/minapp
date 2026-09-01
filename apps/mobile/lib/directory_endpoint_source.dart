import 'package:http/http.dart' as http;

import 'endpoint_validation.dart';

const String minAppDirectoryGoogleDriveFileId =
    '1mNyZWD5utMMkBhvGKhWPloTVOoE05W9u';
const Duration minAppDirectoryFetchTimeout = Duration(seconds: 12);

Future<Uri> loadDirectoryBaseUriFromGoogleDrive({
  http.Client? client,
  DateTime? now,
}) async {
  final bool ownsClient = client == null;
  final http.Client httpClient = client ?? http.Client();

  try {
    final Uri downloadUri = Uri.https(
      'drive.google.com',
      '/uc',
      <String, String>{
        'export': 'download',
        'id': minAppDirectoryGoogleDriveFileId,
        't': (now ?? DateTime.now()).millisecondsSinceEpoch.toString(),
      },
    );

    final http.Response response = await httpClient
        .get(downloadUri)
        .timeout(minAppDirectoryFetchTimeout);

    if (response.statusCode != 200) {
      throw StateError(
        'Google Drive directory endpoint fetch failed: '
        'HTTP ${response.statusCode} from $downloadUri',
      );
    }

    final List<String> nonEmptyLines = response.body
        .split(RegExp(r'\r?\n'))
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .toList(growable: false);

    if (nonEmptyLines.length != 1) {
      throw StateError(
        'Google Drive directory endpoint file must contain exactly one '
        'non-empty line; found ${nonEmptyLines.length}.',
      );
    }

    final Uri? parsed = Uri.tryParse(nonEmptyLines.single);
    if (parsed == null) {
      throw FormatException(
        'Google Drive directory endpoint is not a valid URI.',
        nonEmptyLines.single,
      );
    }

    return validatePublicHttpsBaseUri(
      parsed,
      argumentName: 'Google Drive directory endpoint',
    );
  } finally {
    if (ownsClient) {
      httpClient.close();
    }
  }
}
