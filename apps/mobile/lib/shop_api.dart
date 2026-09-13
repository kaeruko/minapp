import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';

final RegExp _hexIdPattern = RegExp(r'^[0-9a-f]{32}$');
final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

class ShopApp {
  const ShopApp({
    required this.appId,
    required this.version,
    required this.title,
    required this.ownerUserId,
    required this.ownerDisplayName,
    required this.publishedAt,
    required this.sha256,
    this.description,
  });

  final String appId;
  final String version;
  final String title;
  final String ownerUserId;
  final String ownerDisplayName;
  final DateTime publishedAt;
  final String sha256;
  final String? description;

  factory ShopApp.fromJson(Map<String, Object?> json) {
    final String appId = _requiredHexId(json, 'app_id');
    final String version = _shopVersion(json);
    final String ownerUserId = _requiredHexId(json, 'owner_user_id');
    final String ownerDisplayName = _ownerDisplayName(json);
    final String publishedAt = _publishedAt(json);
    final String sha256 = _requiredString(json, 'sha256');
    if (!_sha256Pattern.hasMatch(sha256)) {
      throw const FormatException('Shop app sha256 must be 64 lowercase hexadecimal characters.');
    }
    final String? description = _optionalString(json, 'description');
    if (description != null && description.length > 200) {
      throw const FormatException('Shop app description must be at most 200 characters.');
    }
    return ShopApp(
      appId: appId,
      version: version,
      title: _requiredString(json, 'title'),
      ownerUserId: ownerUserId,
      ownerDisplayName: ownerDisplayName,
      publishedAt: DateTime.parse(publishedAt).toUtc(),
      sha256: sha256,
      description: description,
    );
  }
}

class ShopLaunchGrant {
  const ShopLaunchGrant({required this.url, required this.expiresIn});

  final Uri url;
  final int expiresIn;
}

class ShopDownloadGrant {
  const ShopDownloadGrant({
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

class ShopApiClient {
  ShopApiClient({required Uri baseUri, http.Client? client})
      : _baseUri = _validateBaseUri(baseUri),
        _client = client ?? http.Client();

  final Uri _baseUri;
  final http.Client _client;

  Future<List<ShopApp>> listApps(String accessToken) async {
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'GET',
      path: '/shop/apps',
      accessToken: accessToken,
    );
    final Object? rawApps = payload['apps'];
    if (rawApps is! List<Object?>) {
      throw const FormatException('Shop response has no apps list.');
    }
    return rawApps.map((Object? raw) {
      if (raw is! Map<String, Object?>) {
        throw const FormatException('Shop response contains a non-object app.');
      }
      return ShopApp.fromJson(raw);
    }).toList(growable: false);
  }

  Future<ShopLaunchGrant> createLaunch({
    required String accessToken,
    required ShopApp app,
  }) async {
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'POST',
      path: '/shop/apps/${app.appId}/launch',
      accessToken: accessToken,
      body: <String, Object?>{'version': app.version},
    );
    return ShopLaunchGrant(
      url: _absoluteHttpsUri(payload, 'url'),
      expiresIn: _positiveInt(payload, 'expires_in'),
    );
  }

  Future<ShopDownloadGrant> createDownload({
    required String accessToken,
    required ShopApp app,
  }) async {
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'POST',
      path: '/shop/apps/${app.appId}/download',
      accessToken: accessToken,
      body: <String, Object?>{'version': app.version},
    );
    final String sha256 = _requiredString(payload, 'sha256');
    if (!_sha256Pattern.hasMatch(sha256)) {
      throw const FormatException('Shop download sha256 is invalid.');
    }
    if (sha256 != app.sha256) {
      throw const FormatException('Shop download sha256 does not match the selected listing.');
    }
    return ShopDownloadGrant(
      url: _absoluteHttpsUri(payload, 'url'),
      filename: _requiredString(payload, 'filename'),
      sha256: sha256,
      expiresIn: _positiveInt(payload, 'expires_in'),
    );
  }

  Future<void> report({
    required String accessToken,
    required ShopApp app,
    required String reason,
  }) async {
    if (reason.isEmpty || reason != reason.trim() || reason.length > 80) {
      throw ArgumentError.value(reason, 'reason', 'must be 1-80 trimmed characters');
    }
    await _jsonRequest(
      method: 'POST',
      path: '/shop/apps/${app.appId}/reports',
      accessToken: accessToken,
      body: <String, Object?>{
        'version': app.version,
        'reason': reason,
      },
    );
  }

  Future<void> setVisibility({
    required String accessToken,
    required String appId,
    required String visibility,
  }) async {
    if (!_hexIdPattern.hasMatch(appId)) {
      throw ArgumentError.value(appId, 'appId', 'must be a lowercase 32-character hex id');
    }
    if (visibility != 'listed' && visibility != 'unlisted') {
      throw ArgumentError.value(visibility, 'visibility', 'must be listed or unlisted');
    }
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'PUT',
      path: '/apps/$appId/shop-visibility',
      accessToken: accessToken,
      body: <String, Object?>{'visibility': visibility},
    );
    if (_requiredString(payload, 'app_id') != appId ||
        _requiredString(payload, 'shop_visibility') != visibility) {
      throw const FormatException('Shop visibility response does not match the request.');
    }
  }

  Future<Map<String, Object?>> _jsonRequest({
    required String method,
    required String path,
    required String accessToken,
    Map<String, Object?>? body,
  }) async {
    if (!path.startsWith('/')) {
      throw ArgumentError.value(path, 'path', 'must start with /.');
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
        response = await _client.post(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        );
      case 'PUT':
        if (body == null) throw ArgumentError('PUT requires a JSON body.');
        response = await _client.put(uri, headers: headers, body: jsonEncode(body));
      default:
        throw ArgumentError.value(method, 'method', 'unsupported HTTP method');
    }

    final String? contentType = response.headers['content-type'];
    if (contentType == null ||
        !contentType.toLowerCase().startsWith('application/json')) {
      throw FormatException(
        'Shop API returned a non-JSON response (HTTP ${response.statusCode}).',
      );
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Shop API returned an unexpected JSON payload.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        code: decoded['error'] is String ? decoded['error']! as String : 'api_error',
        message: decoded['message'] is String
            ? decoded['message']! as String
            : 'Shop API request failed with HTTP ${response.statusCode}.',
      );
    }
    return decoded;
  }

  static Uri _validateBaseUri(Uri uri) {
    if (uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw ArgumentError.value(
        uri,
        'baseUri',
        'Shop API base URI must be absolute HTTPS without credentials, query, or fragment.',
      );
    }
    return uri;
  }
}

String _shopVersion(Map<String, Object?> json) {
  final Object? explicit = json['version'];
  final Object? classic = json['version_id'];
  if (explicit != null && explicit is! String) {
    throw const FormatException('Shop app version must be a string.');
  }
  if (classic != null && classic is! String) {
    throw const FormatException('Shop app version_id must be a string.');
  }
  if (explicit is String && classic is String && explicit != classic) {
    throw const FormatException('Shop app version and version_id disagree.');
  }
  final String? value = explicit is String ? explicit : classic as String?;
  if (value == null || value.isEmpty || value.length > 32) {
    throw const FormatException('Shop app has no valid version token.');
  }
  return value;
}

String _publishedAt(Map<String, Object?> json) {
  final Object? hosted = json['published_at'];
  final Object? classic = json['reviewed_at'];
  if (hosted != null && hosted is! String) {
    throw const FormatException('Shop app published_at must be a string.');
  }
  if (classic != null && classic is! String) {
    throw const FormatException('Shop app reviewed_at must be a string.');
  }
  final String? value = hosted is String ? hosted : classic as String?;
  if (value == null || value.isEmpty) {
    throw const FormatException('Shop app has no publication timestamp.');
  }
  return value;
}

String _ownerDisplayName(Map<String, Object?> json) {
  final Object? display = json['owner_display_name'];
  final Object? login = json['owner_login_id'];
  final Object? raw = display ?? login;
  if (raw is! String || raw.isEmpty || raw != raw.trim() || raw.length > 80) {
    throw const FormatException('Shop app has no valid owner display name.');
  }
  return raw;
}

String _requiredString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('JSON field $key must be a non-empty string.');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw FormatException('JSON field $key must be null or a non-empty string.');
  }
  return value;
}

String _requiredHexId(Map<String, Object?> json, String key) {
  final String value = _requiredString(json, key);
  if (!_hexIdPattern.hasMatch(value)) {
    throw FormatException('JSON field $key must be a 32-character lowercase hexadecimal id.');
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
