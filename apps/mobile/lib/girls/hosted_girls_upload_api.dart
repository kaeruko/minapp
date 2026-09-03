import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api.dart';
import 'hosted_girls_api.dart';

const int maxGirlsZipUploadBytes = 2 * 1024 * 1024;
final RegExp _hostedIdPattern = RegExp(r'^[0-9a-f]{32}$');

class HostedGirlsUploadApi {
  HostedGirlsUploadApi({required Uri baseUri, http.Client? client})
      : _baseUri = baseUri,
        _client = client ?? http.Client(),
        _ownsClient = client == null {
    if (baseUri.scheme != 'https' ||
        !baseUri.hasAuthority ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.query.isNotEmpty ||
        baseUri.fragment.isNotEmpty) {
      throw ArgumentError.value(
        baseUri,
        'baseUri',
        'Hosted API base URI must be an absolute HTTPS URL without credentials, query, or fragment.',
      );
    }
  }

  final Uri _baseUri;
  final http.Client _client;
  final bool _ownsClient;

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<HostedGroupApp> createFromZip({
    required String accessToken,
    required String groupId,
    required String title,
    required Uint8List zipBytes,
  }) async {
    _validateAccessToken(accessToken);
    _validateId(groupId, 'groupId');
    if (title.isEmpty || title != title.trim() || title.length > 80) {
      throw ArgumentError.value(
        title,
        'title',
        'must be a trimmed non-empty title up to 80 characters',
      );
    }
    if (zipBytes.isEmpty || zipBytes.length > maxGirlsZipUploadBytes) {
      throw ArgumentError.value(
        zipBytes.length,
        'zipBytes',
        'ZIP must contain 1 to $maxGirlsZipUploadBytes bytes',
      );
    }

    final Uri uri = _baseUri
        .resolve('/hosted/groups/$groupId/apps/upload')
        .replace(queryParameters: <String, String>{'title': title});
    final http.Response response = await _client.post(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/zip',
      },
      body: zipBytes,
    );
    final Map<String, Object?> payload = _decodeJsonResponse(response);
    return HostedGroupApp.fromJson(payload);
  }

  Future<int> publish({
    required String accessToken,
    required String groupId,
    required String appId,
    required int revision,
  }) async {
    _validateAccessToken(accessToken);
    _validateId(groupId, 'groupId');
    _validateId(appId, 'appId');
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be positive');
    }

    final Uri uri = _baseUri.resolve(
      '/hosted/groups/$groupId/apps/$appId/publish',
    );
    final http.Response response = await _client.post(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, Object?>{'revision': revision}),
    );
    final Map<String, Object?> payload = _decodeJsonResponse(response);
    final Object? rawVersion = payload['published_version'];
    final Object? rawRevision = payload['source_revision'];
    if (rawVersion is! int || rawVersion < 1 || rawRevision != revision) {
      throw const FormatException(
        'Publish response has invalid published_version or source_revision.',
      );
    }
    return rawVersion;
  }

  Map<String, Object?> _decodeJsonResponse(http.Response response) {
    final String? contentType = response.headers['content-type'];
    if (contentType == null ||
        !contentType.toLowerCase().startsWith('application/json')) {
      throw FormatException(
        'API returned a non-JSON response (HTTP ${response.statusCode}).',
      );
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('API returned an unexpected JSON payload.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final Object? rawCode = decoded['error'];
      final Object? rawMessage = decoded['message'];
      if (rawCode is! String ||
          rawCode.isEmpty ||
          rawMessage is! String ||
          rawMessage.isEmpty) {
        throw const FormatException(
          'API error response is missing error or message.',
        );
      }
      throw ApiException(
        statusCode: response.statusCode,
        code: rawCode,
        message: rawMessage,
      );
    }
    return decoded;
  }
}

void _validateAccessToken(String accessToken) {
  if (accessToken.isEmpty) {
    throw ArgumentError.value(accessToken, 'accessToken', 'must not be empty');
  }
}

void _validateId(String value, String label) {
  if (!_hostedIdPattern.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      label,
      'must be a 32-character lowercase hexadecimal ID',
    );
  }
}
