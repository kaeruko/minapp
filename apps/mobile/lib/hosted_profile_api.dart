import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';

const int maxHostedDisplayNameLength = 40;

class HostedProfile {
  const HostedProfile({
    required this.userId,
    required this.loginId,
    required this.role,
    required this.displayName,
  });

  final String userId;
  final String loginId;
  final String role;
  final String? displayName;

  factory HostedProfile.fromJson(Map<String, Object?> json) {
    const Set<String> expected = <String>{
      'user_id',
      'login_id',
      'role',
      'display_name',
    };
    if (json.keys.toSet().difference(expected).isNotEmpty ||
        expected.difference(json.keys.toSet()).isNotEmpty) {
      throw const FormatException(
        'Display-name profile returned unexpected fields.',
      );
    }
    final Object? userId = json['user_id'];
    final Object? loginId = json['login_id'];
    final Object? role = json['role'];
    final Object? displayName = json['display_name'];
    if (userId is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(userId)) {
      throw const FormatException('Display-name profile has invalid user_id.');
    }
    if (loginId is! String || loginId.isEmpty || role != 'user') {
      throw const FormatException('Display-name profile identity is invalid.');
    }
    if (displayName != null && !_validDisplayName(displayName)) {
      throw const FormatException(
        'Display-name profile has invalid display_name.',
      );
    }
    return HostedProfile(
      userId: userId,
      loginId: loginId,
      role: role as String,
      displayName: displayName as String?,
    );
  }
}

class HostedProfileApi {
  HostedProfileApi({required Uri baseUri, http.Client? client})
      : _baseUri = _validateBaseUri(baseUri),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final Uri _baseUri;
  final http.Client _client;
  final bool _ownsClient;

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<HostedProfile> fetch(String accessToken) {
    return _request(method: 'GET', accessToken: accessToken);
  }

  Future<HostedProfile> updateDisplayName({
    required String accessToken,
    required String displayName,
  }) {
    if (!_validDisplayName(displayName)) {
      throw ArgumentError.value(
        displayName,
        'displayName',
        'must be 1-$maxHostedDisplayNameLength trimmed printable characters',
      );
    }
    return _request(
      method: 'PATCH',
      accessToken: accessToken,
      displayName: displayName,
    );
  }

  Future<HostedProfile> _request({
    required String method,
    required String accessToken,
    String? displayName,
  }) async {
    if (accessToken.isEmpty) {
      throw ArgumentError.value(
          accessToken, 'accessToken', 'must not be empty');
    }
    final Uri uri = _baseUri.resolve('/hosted/me/display-name');
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $accessToken',
    };
    final http.Response response = switch (method) {
      'GET' when displayName == null =>
        await _client.get(uri, headers: headers),
      'PATCH' when displayName != null => await _client.patch(
          uri,
          headers: <String, String>{
            ...headers,
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, Object?>{'display_name': displayName}),
        ),
      _ => throw ArgumentError('Invalid display-name request.'),
    };
    final String? contentType = response.headers['content-type'];
    if (contentType == null ||
        !contentType.toLowerCase().startsWith('application/json')) {
      throw FormatException(
        'Display-name API returned non-JSON (HTTP ${response.statusCode}).',
      );
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException(
        'Display-name API returned an unexpected JSON payload.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        code: decoded['error'] is String
            ? decoded['error']! as String
            : 'api_error',
        message: decoded['message'] is String
            ? decoded['message']! as String
            : 'Display-name API request failed.',
      );
    }
    return HostedProfile.fromJson(decoded);
  }
}

bool _validDisplayName(Object? value) {
  return value is String &&
      value.isNotEmpty &&
      value.length <= maxHostedDisplayNameLength &&
      value == value.trim() &&
      !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value);
}

Uri _validateBaseUri(Uri uri) {
  if (uri.scheme != 'https' ||
      !uri.hasAuthority ||
      uri.userInfo.isNotEmpty ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty) {
    throw ArgumentError.value(uri, 'baseUri', 'must be an absolute HTTPS URI');
  }
  return uri;
}
