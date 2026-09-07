import 'package:http/http.dart' as http;

import 'endpoint_validation.dart';

const String minAppHostedGoogleDriveFileId =
    '17BOAlIhz-DPxtsWYMl68Ze0XQILb5bq2';
const Duration minAppHostedFetchTimeout = Duration(seconds: 12);

Future<Uri> loadHostedBaseUriFromGoogleDrive({
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
        'id': minAppHostedGoogleDriveFileId,
        't': (now ?? DateTime.now()).millisecondsSinceEpoch.toString(),
      },
    );
    final http.Response response =
        await httpClient.get(downloadUri).timeout(minAppHostedFetchTimeout);
    if (response.statusCode != 200) {
      throw StateError(
        'Google Drive Hosted endpoint fetch failed: '
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
        'Google Drive Hosted endpoint file must contain exactly one '
        'non-empty line; found ${nonEmptyLines.length}.',
      );
    }
    final Uri? parsed = Uri.tryParse(nonEmptyLines.single);
    if (parsed == null) {
      throw FormatException(
        'Google Drive Hosted endpoint is not a valid URI.',
        nonEmptyLines.single,
      );
    }
    return validatePublicHttpsBaseUri(
      parsed,
      argumentName: 'Google Drive Hosted endpoint',
    );
  } finally {
    if (ownsClient) httpClient.close();
  }
}
