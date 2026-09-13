import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api.dart';

final RegExp _hexIdPattern = RegExp(r'^[0-9a-f]{32}$');
final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
final RegExp _versionPattern = RegExp(r'^[1-9][0-9]*$');

class GirlsShopApp {
  const GirlsShopApp({
    required this.appId,
    required this.version,
    required this.title,
    required this.ownerUserId,
    required this.ownerDisplayName,
    required this.publishedAt,
    required this.sha256,
  });

  final String appId;
  final String version;
  final String title;
  final String ownerUserId;
  final String ownerDisplayName;
  final DateTime publishedAt;
  final String sha256;

  factory GirlsShopApp.fromJson(Map<String, Object?> json) {
    _requireExactFields(
      json,
      const <String>{
        'app_id',
        'version',
        'title',
        'owner_user_id',
        'owner_display_name',
        'published_at',
        'sha256',
      },
      'Girls shop app',
    );
    final String appId = _requiredString(json, 'app_id');
    final String ownerUserId = _requiredString(json, 'owner_user_id');
    final String version = _requiredString(json, 'version');
    final String sha256 = _requiredString(json, 'sha256');
    if (!_hexIdPattern.hasMatch(appId)) {
      throw const FormatException('Girls shop app_id is invalid.');
    }
    if (!_hexIdPattern.hasMatch(ownerUserId)) {
      throw const FormatException('Girls shop owner_user_id is invalid.');
    }
    if (!_versionPattern.hasMatch(version)) {
      throw const FormatException('Girls shop version is invalid.');
    }
    if (!_sha256Pattern.hasMatch(sha256)) {
      throw const FormatException('Girls shop sha256 is invalid.');
    }
    final String ownerDisplayName = _requiredString(json, 'owner_display_name');
    if (ownerDisplayName != ownerDisplayName.trim() || ownerDisplayName.length > 80) {
      throw const FormatException('Girls shop owner_display_name is invalid.');
    }
    return GirlsShopApp(
      appId: appId,
      version: version,
      title: _requiredString(json, 'title'),
      ownerUserId: ownerUserId,
      ownerDisplayName: ownerDisplayName,
      publishedAt: DateTime.parse(_requiredString(json, 'published_at')).toUtc(),
      sha256: sha256,
    );
  }
}

class GirlsShopLaunchGrant {
  const GirlsShopLaunchGrant({
    required this.contentUri,
    required this.runtimeToken,
    required this.expiresIn,
  });

  final Uri contentUri;
  final String runtimeToken;
  final int expiresIn;
}

class GirlsShopDownloadGrant {
  const GirlsShopDownloadGrant({
    required this.url,
    required this.filename,
    required this.sha256,
    required this.expiresIn,
  });

  final Uri url;
  final String filename;
  final String sha256;
  final int expiresIn;
}

class GirlsShopApi {
  GirlsShopApi({required Uri baseUri, http.Client? client})
      : _baseUri = _validateBaseUri(baseUri),
        _client = client ?? http.Client();

  final Uri _baseUri;
  final http.Client _client;

  void close() => _client.close();

  Future<List<GirlsShopApp>> listApps(String accessToken) async {
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'GET',
      path: '/shop/apps',
      accessToken: accessToken,
    );
    _requireExactFields(payload, const <String>{'apps'}, 'Girls shop list');
    final Object? rawApps = payload['apps'];
    if (rawApps is! List<Object?>) {
      throw const FormatException('Girls shop response has no apps list.');
    }
    return rawApps.map((Object? raw) {
      if (raw is! Map<String, Object?>) {
        throw const FormatException('Girls shop contains a non-object app.');
      }
      return GirlsShopApp.fromJson(raw);
    }).toList(growable: false);
  }

  Future<GirlsShopLaunchGrant> createLaunch({
    required String accessToken,
    required GirlsShopApp app,
  }) async {
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'POST',
      path: '/shop/apps/${app.appId}/launch',
      accessToken: accessToken,
      body: <String, Object?>{'version': app.version},
    );
    _requireExactFields(
      payload,
      const <String>{'url', 'runtime_token', 'expires_in'},
      'Girls shop launch',
    );
    final String runtimeToken = _requiredString(payload, 'runtime_token');
    if (runtimeToken.length < 32 || runtimeToken.length > 128) {
      throw const FormatException('Girls shop runtime_token is invalid.');
    }
    return GirlsShopLaunchGrant(
      contentUri: _absoluteHttpsUri(payload, 'url'),
      runtimeToken: runtimeToken,
      expiresIn: _positiveInt(payload, 'expires_in'),
    );
  }

  Future<GirlsShopDownloadGrant> createDownload({
    required String accessToken,
    required GirlsShopApp app,
  }) async {
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'POST',
      path: '/shop/apps/${app.appId}/download',
      accessToken: accessToken,
      body: <String, Object?>{'version': app.version},
    );
    _requireExactFields(
      payload,
      const <String>{'url', 'filename', 'sha256', 'expires_in'},
      'Girls shop download',
    );
    final String sha256 = _requiredString(payload, 'sha256');
    if (!_sha256Pattern.hasMatch(sha256)) {
      throw const FormatException('Girls shop download sha256 is invalid.');
    }
    if (sha256 != app.sha256) {
      throw const FormatException('Girls shop download sha256 does not match the listing.');
    }
    return GirlsShopDownloadGrant(
      url: _absoluteHttpsUri(payload, 'url'),
      filename: _requiredString(payload, 'filename'),
      sha256: sha256,
      expiresIn: _positiveInt(payload, 'expires_in'),
    );
  }

  Future<void> report({
    required String accessToken,
    required GirlsShopApp app,
    required String reason,
  }) async {
    if (reason.isEmpty || reason != reason.trim() || reason.length > 80) {
      throw ArgumentError.value(reason, 'reason', 'must be 1-80 trimmed characters');
    }
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'POST',
      path: '/shop/apps/${app.appId}/reports',
      accessToken: accessToken,
      body: <String, Object?>{'version': app.version, 'reason': reason},
    );
    _requireExactFields(
      payload,
      const <String>{'report_id', 'status', 'created_at'},
      'Girls shop report',
    );
    if (_requiredString(payload, 'status') != 'received') {
      throw const FormatException('Girls shop report status is invalid.');
    }
    _requiredString(payload, 'report_id');
    DateTime.parse(_requiredString(payload, 'created_at')).toUtc();
  }

  Future<void> setVisibility({
    required String accessToken,
    required String appId,
    required bool listed,
  }) async {
    if (!_hexIdPattern.hasMatch(appId)) {
      throw ArgumentError.value(appId, 'appId', 'must be a lowercase 32-character hex id');
    }
    final String visibility = listed ? 'listed' : 'unlisted';
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'PUT',
      path: '/apps/$appId/shop-visibility',
      accessToken: accessToken,
      body: <String, Object?>{'visibility': visibility},
    );
    _requireExactFields(
      payload,
      const <String>{'app_id', 'shop_visibility'},
      'Girls shop visibility',
    );
    if (_requiredString(payload, 'app_id') != appId ||
        _requiredString(payload, 'shop_visibility') != visibility) {
      throw const FormatException('Girls shop visibility response does not match the request.');
    }
  }

  Future<Map<String, Object?>> _jsonRequest({
    required String method,
    required String path,
    required String accessToken,
    Map<String, Object?>? body,
  }) async {
    if (!path.startsWith('/') || path.startsWith('//')) {
      throw ArgumentError.value(path, 'path', 'must be origin-relative');
    }
    if (accessToken.isEmpty) {
      throw ArgumentError.value(accessToken, 'accessToken', 'must not be empty');
    }
    final Uri uri = _baseUri.resolve(path);
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $accessToken',
    };
    if (body != null) headers['Content-Type'] = 'application/json';

    late final http.Response response;
    switch (method) {
      case 'GET':
        if (body != null) throw ArgumentError('GET must not contain a body.');
        response = await _client.get(uri, headers: headers);
      case 'POST':
        if (body == null) throw ArgumentError('POST requires a JSON body.');
        response = await _client.post(uri, headers: headers, body: jsonEncode(body));
      case 'PUT':
        if (body == null) throw ArgumentError('PUT requires a JSON body.');
        response = await _client.put(uri, headers: headers, body: jsonEncode(body));
      default:
        throw ArgumentError.value(method, 'method', 'unsupported HTTP method');
    }

    final String? contentType = response.headers['content-type'];
    if (contentType == null || !contentType.toLowerCase().startsWith('application/json')) {
      throw FormatException(
        'Girls shop API returned non-JSON (HTTP ${response.statusCode}).',
      );
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Girls shop API returned an unexpected JSON payload.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        code: decoded['error'] is String ? decoded['error']! as String : 'api_error',
        message: decoded['message'] is String
            ? decoded['message']! as String
            : 'Girls shop API request failed with HTTP ${response.statusCode}.',
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
      'Girls shop API base URI must be absolute HTTPS without credentials, query, or fragment.',
    );
  }
  return uri;
}

void _requireExactFields(
  Map<String, Object?> json,
  Set<String> expected,
  String context,
) {
  final Set<String> actual = json.keys.toSet();
  if (actual.length != expected.length || !actual.containsAll(expected)) {
    throw FormatException('$context response schema is invalid.');
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('JSON field $key must be a non-empty string.');
  }
  return value;
}

int _positiveInt(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! int || value <= 0) {
    throw FormatException('JSON field $key must be a positive integer.');
  }
  return value;
}

Uri _absoluteHttpsUri(Map<String, Object?> json, String key) {
  final Uri uri = Uri.parse(_requiredString(json, key));
  if (uri.scheme != 'https' || !uri.hasAuthority || uri.fragment.isNotEmpty) {
    throw FormatException('JSON field $key must be an absolute HTTPS URL without fragment.');
  }
  return uri;
}
