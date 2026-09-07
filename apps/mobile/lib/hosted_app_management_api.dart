import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api.dart';
import 'hosted_api.dart';

const int maxHostedZipUploadBytes = 2 * 1024 * 1024;
final RegExp _managedIdPattern = RegExp(r'^[0-9a-f]{32}$');
final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

class HostedSourceDownload {
  const HostedSourceDownload({
    required this.bytes,
    required this.revision,
    required this.sha256,
  });

  final Uint8List bytes;
  final int revision;
  final String sha256;
}

class HostedAppStats {
  const HostedAppStats({
    required this.totalPlays,
    required this.uniqueUsers,
    required this.monthlyPlays,
  });

  final int totalPlays;
  final int uniqueUsers;
  final int monthlyPlays;

  factory HostedAppStats.fromJson(Map<String, Object?> json) {
    final Set<String> actual = json.keys.toSet();
    const Set<String> expected = <String>{
      'total_plays',
      'unique_users',
      'monthly_plays',
    };
    if (actual.length != expected.length || !actual.containsAll(expected)) {
      throw const FormatException('Managed app stats have unexpected fields.');
    }

    int read(String key) {
      final Object? value = json[key];
      if (value is! int || value < 0) {
        throw FormatException('Managed app stats have invalid $key.');
      }
      return value;
    }

    return HostedAppStats(
      totalPlays: read('total_plays'),
      uniqueUsers: read('unique_users'),
      monthlyPlays: read('monthly_plays'),
    );
  }
}

class ManagedHostedApp {
  const ManagedHostedApp({
    required this.app,
    required this.stats,
    required this.visibility,
    required this.sourceRevision,
    required this.sourceUpdatedAt,
    required this.publishedAt,
    required this.groupName,
  });

  final HostedGroupApp app;
  final HostedAppStats stats;
  final String visibility;
  final int? sourceRevision;
  final DateTime? sourceUpdatedAt;
  final DateTime? publishedAt;
  final String? groupName;

  bool get isHidden => visibility == 'hidden';

  factory ManagedHostedApp.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> appJson = Map<String, Object?>.from(json)
      ..remove('stats')
      ..remove('visibility')
      ..remove('group_name')
      ..remove('source_history')
      ..remove('published_history');
    final HostedGroupApp app = HostedGroupApp.fromJson(appJson);

    final Object? rawStats = json['stats'];
    if (rawStats is! Map<String, Object?>) {
      throw const FormatException('Managed app has invalid stats.');
    }
    final Object? rawVisibility = json['visibility'];
    if (rawVisibility != 'visible' && rawVisibility != 'hidden') {
      throw const FormatException('Managed app has invalid visibility.');
    }
    final Object? rawRevision = json['source_revision'];
    if (rawRevision != null && (rawRevision is! int || rawRevision < 1)) {
      throw const FormatException('Managed app has invalid source_revision.');
    }

    DateTime? optionalDate(String key) {
      final Object? raw = json[key];
      if (raw == null) return null;
      if (raw is! String || raw.isEmpty) {
        throw FormatException('Managed app has invalid $key.');
      }
      return DateTime.parse(raw).toUtc();
    }

    final Object? rawGroupName = json['group_name'];
    if (rawGroupName != null &&
        (rawGroupName is! String || rawGroupName.isEmpty)) {
      throw const FormatException('Managed app has invalid group_name.');
    }

    return ManagedHostedApp(
      app: app,
      stats: HostedAppStats.fromJson(rawStats),
      visibility: rawVisibility as String,
      sourceRevision: rawRevision as int?,
      sourceUpdatedAt: optionalDate('source_updated_at'),
      publishedAt: optionalDate('published_at'),
      groupName: rawGroupName as String?,
    );
  }
}

class HostedSourceHistoryItem {
  const HostedSourceHistoryItem({
    required this.revision,
    required this.createdAt,
  });

  final int revision;
  final DateTime createdAt;

  factory HostedSourceHistoryItem.fromJson(Map<String, Object?> json) {
    final Object? revision = json['revision'];
    final Object? createdAt = json['created_at'];
    final Object? sha256 = json['sha256'];
    if (revision is! int ||
        revision < 1 ||
        createdAt is! String ||
        createdAt.isEmpty ||
        sha256 is! String ||
        sha256.length != 64) {
      throw const FormatException('Managed source history entry is invalid.');
    }
    return HostedSourceHistoryItem(
      revision: revision,
      createdAt: DateTime.parse(createdAt).toUtc(),
    );
  }
}

class HostedPublishedHistoryItem {
  const HostedPublishedHistoryItem({
    required this.version,
    required this.sourceRevision,
    required this.publishedAt,
  });

  final int version;
  final int sourceRevision;
  final DateTime publishedAt;

  factory HostedPublishedHistoryItem.fromJson(Map<String, Object?> json) {
    final Object? version = json['version'];
    final Object? revision = json['source_revision'];
    final Object? publishedAt = json['published_at'];
    final Object? sha256 = json['sha256'];
    if (version is! int ||
        version < 1 ||
        revision is! int ||
        revision < 1 ||
        publishedAt is! String ||
        publishedAt.isEmpty ||
        sha256 is! String ||
        sha256.length != 64) {
      throw const FormatException(
        'Managed published history entry is invalid.',
      );
    }
    return HostedPublishedHistoryItem(
      version: version,
      sourceRevision: revision,
      publishedAt: DateTime.parse(publishedAt).toUtc(),
    );
  }
}

class ManagedHostedAppDetail {
  const ManagedHostedAppDetail({
    required this.summary,
    required this.sourceHistory,
    required this.publishedHistory,
  });

  final ManagedHostedApp summary;
  final List<HostedSourceHistoryItem> sourceHistory;
  final List<HostedPublishedHistoryItem> publishedHistory;

  factory ManagedHostedAppDetail.fromJson(Map<String, Object?> json) {
    final Object? rawSource = json['source_history'];
    final Object? rawPublished = json['published_history'];
    if (rawSource is! List<Object?> || rawPublished is! List<Object?>) {
      throw const FormatException('Managed app detail history is invalid.');
    }
    return ManagedHostedAppDetail(
      summary: ManagedHostedApp.fromJson(json),
      sourceHistory: rawSource
          .map((Object? value) {
            if (value is! Map<String, Object?>) {
              throw const FormatException(
                'Managed source history contains a non-object.',
              );
            }
            return HostedSourceHistoryItem.fromJson(value);
          })
          .toList(growable: false),
      publishedHistory: rawPublished
          .map((Object? value) {
            if (value is! Map<String, Object?>) {
              throw const FormatException(
                'Managed published history contains a non-object.',
              );
            }
            return HostedPublishedHistoryItem.fromJson(value);
          })
          .toList(growable: false),
    );
  }
}

class HostedAppManagementApi {
  HostedAppManagementApi({required Uri baseUri, http.Client? client})
    : _baseUri = _validateBaseUri(baseUri),
      _client = client ?? http.Client(),
      _ownsClient = client == null;

  final Uri _baseUri;
  final http.Client _client;
  final bool _ownsClient;

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<List<ManagedHostedApp>> listApps(String accessToken) async {
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'GET',
      path: '/hosted/my/apps',
      accessToken: accessToken,
    );
    final Set<String> actual = payload.keys.toSet();
    if (actual.length != 1 || !actual.contains('apps')) {
      throw const FormatException(
        'Managed apps response has unexpected fields.',
      );
    }
    final Object? rawApps = payload['apps'];
    if (rawApps is! List<Object?>) {
      throw const FormatException('Managed apps response has no apps list.');
    }
    return rawApps
        .map((Object? value) {
          if (value is! Map<String, Object?>) {
            throw const FormatException(
              'Managed apps response contains a non-object.',
            );
          }
          return ManagedHostedApp.fromJson(value);
        })
        .toList(growable: false);
  }

  Future<ManagedHostedAppDetail> getApp({
    required String accessToken,
    required String appId,
  }) async {
    _validateId(appId, 'appId');
    return ManagedHostedAppDetail.fromJson(
      await _jsonRequest(
        method: 'GET',
        path: '/hosted/my/apps/$appId',
        accessToken: accessToken,
      ),
    );
  }

  Future<ManagedHostedApp> setHidden({
    required String accessToken,
    required String appId,
    required bool hidden,
  }) async {
    _validateId(appId, 'appId');
    return ManagedHostedApp.fromJson(
      await _jsonRequest(
        method: 'POST',
        path: '/hosted/my/apps/$appId/visibility',
        accessToken: accessToken,
        body: <String, Object?>{'hidden': hidden},
      ),
    );
  }

  Future<HostedSourceDownload> downloadSource({
    required String accessToken,
    required String groupId,
    required String appId,
  }) async {
    _validateToken(accessToken);
    _validateId(groupId, 'groupId');
    _validateId(appId, 'appId');
    final http.Response response = await _client.get(
      _baseUri.resolve('/hosted/groups/$groupId/apps/$appId/source'),
      headers: <String, String>{
        'Accept': 'application/zip',
        'Authorization': 'Bearer $accessToken',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _decodeJsonResponse(response);
      throw StateError('Unreachable source download error path.');
    }
    final String contentType = (response.headers['content-type'] ?? '')
        .split(';')
        .first
        .trim()
        .toLowerCase();
    if (contentType != 'application/zip') {
      throw FormatException(
        'Source download returned unexpected content type: $contentType.',
      );
    }
    if (response.bodyBytes.isEmpty ||
        response.bodyBytes.length > maxHostedZipUploadBytes) {
      throw const FormatException(
        'Source download returned an invalid ZIP size.',
      );
    }
    final int? revision = int.tryParse(
      response.headers['x-minapp-source-revision'] ?? '',
    );
    final String sha256 = response.headers['x-minapp-source-sha256'] ?? '';
    if (revision == null || revision < 1 || !_sha256Pattern.hasMatch(sha256)) {
      throw const FormatException(
        'Source download metadata headers are invalid.',
      );
    }
    return HostedSourceDownload(
      bytes: Uint8List.fromList(response.bodyBytes),
      revision: revision,
      sha256: sha256,
    );
  }

  Future<ManagedHostedApp> setGroupHidden({
    required String accessToken,
    required String groupId,
    required String appId,
    required bool hidden,
  }) async {
    _validateId(groupId, 'groupId');
    _validateId(appId, 'appId');
    return ManagedHostedApp.fromJson(
      await _jsonRequest(
        method: 'POST',
        path: '/hosted/groups/$groupId/apps/$appId/visibility',
        accessToken: accessToken,
        body: <String, Object?>{'hidden': hidden},
      ),
    );
  }

  Future<int> updateSource({
    required String accessToken,
    required String groupId,
    required String appId,
    required int expectedRevision,
    required Uint8List zipBytes,
  }) async {
    _validateToken(accessToken);
    _validateId(groupId, 'groupId');
    _validateId(appId, 'appId');
    if (expectedRevision < 1) {
      throw ArgumentError.value(
        expectedRevision,
        'expectedRevision',
        'must be positive',
      );
    }
    if (zipBytes.isEmpty || zipBytes.length > maxHostedZipUploadBytes) {
      throw ArgumentError.value(
        zipBytes.length,
        'zipBytes',
        'ZIP must contain 1 to $maxHostedZipUploadBytes bytes',
      );
    }
    final Uri uri = _baseUri
        .resolve('/hosted/groups/$groupId/apps/$appId/source')
        .replace(
          queryParameters: <String, String>{'revision': '$expectedRevision'},
        );
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
    final Object? revision = payload['revision'];
    if (revision is! int || revision != expectedRevision + 1) {
      throw const FormatException(
        'Source update returned an invalid revision.',
      );
    }
    return revision;
  }

  Future<int> publish({
    required String accessToken,
    required String groupId,
    required String appId,
    required int revision,
  }) async {
    _validateToken(accessToken);
    _validateId(groupId, 'groupId');
    _validateId(appId, 'appId');
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be positive');
    }
    final http.Response response = await _client.post(
      _baseUri.resolve('/hosted/groups/$groupId/apps/$appId/publish'),
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, Object?>{'revision': revision}),
    );
    final Map<String, Object?> payload = _decodeJsonResponse(response);
    final Object? version = payload['published_version'];
    final Object? sourceRevision = payload['source_revision'];
    if (version is! int || version < 1 || sourceRevision != revision) {
      throw const FormatException('Publish returned invalid version metadata.');
    }
    return version;
  }

  Future<void> deleteApp({
    required String accessToken,
    required String groupId,
    required String appId,
  }) async {
    _validateToken(accessToken);
    _validateId(groupId, 'groupId');
    _validateId(appId, 'appId');
    final http.Response response = await _client.delete(
      _baseUri.resolve('/hosted/groups/$groupId/apps/$appId'),
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    );
    if (response.statusCode == 204) {
      if (response.bodyBytes.isNotEmpty) {
        throw const FormatException('Delete response must have an empty body.');
      }
      return;
    }
    _decodeJsonResponse(response);
    throw StateError('Unreachable app deletion error path.');
  }

  Future<Map<String, Object?>> _jsonRequest({
    required String method,
    required String path,
    required String accessToken,
    Map<String, Object?>? body,
  }) async {
    _validateToken(accessToken);
    final Uri uri = _baseUri.resolve(path);
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $accessToken',
    };
    if (body != null) headers['Content-Type'] = 'application/json';

    late final http.Response response;
    switch (method) {
      case 'GET':
        if (body != null) {
          throw ArgumentError('GET request must not contain a body.');
        }
        response = await _client.get(uri, headers: headers);
      case 'POST':
        response = await _client.post(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        );
      default:
        throw ArgumentError.value(method, 'method', 'unsupported method');
    }
    return _decodeJsonResponse(response);
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
      final Object? error = decoded['error'];
      final Object? message = decoded['message'];
      if (error is! String ||
          error.isEmpty ||
          message is! String ||
          message.isEmpty) {
        throw const FormatException(
          'API error response is missing error or message.',
        );
      }
      throw ApiException(
        statusCode: response.statusCode,
        code: error,
        message: message,
      );
    }
    return decoded;
  }
}

Uri _validateBaseUri(Uri uri) {
  if (uri.scheme != 'https' ||
      !uri.hasAuthority ||
      uri.userInfo.isNotEmpty ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty) {
    throw ArgumentError.value(
      uri,
      'baseUri',
      'must be an absolute HTTPS URI without credentials, query, or fragment',
    );
  }
  return uri;
}

void _validateToken(String accessToken) {
  if (accessToken.isEmpty) {
    throw ArgumentError.value(accessToken, 'accessToken', 'must not be empty');
  }
}

void _validateId(String value, String label) {
  if (!_managedIdPattern.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      label,
      'must be a 32-character lowercase hexadecimal ID',
    );
  }
}
