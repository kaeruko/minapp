import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';

final RegExp _hostedGroupIdPattern = RegExp(r'^[0-9a-f]{32}$');

class HostedOwnershipTransferResult {
  const HostedOwnershipTransferResult({
    required this.groupId,
    required this.ownerUserId,
  });

  final String groupId;
  final String ownerUserId;

  factory HostedOwnershipTransferResult.fromJson(
    Map<String, Object?> json,
  ) {
    final Set<String> actual = json.keys.toSet();
    const Set<String> expected = <String>{'group_id', 'owner_user_id'};
    if (actual.length != expected.length || !actual.containsAll(expected)) {
      throw const FormatException(
        'Ownership transfer response has unexpected fields.',
      );
    }
    final String groupId = _requiredId(json, 'group_id');
    final String ownerUserId = _requiredId(json, 'owner_user_id');
    return HostedOwnershipTransferResult(
      groupId: groupId,
      ownerUserId: ownerUserId,
    );
  }
}

class HostedGroupManagementApi {
  HostedGroupManagementApi({required Uri baseUri, http.Client? client})
      : _baseUri = _validateBaseUri(baseUri),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final Uri _baseUri;
  final http.Client _client;
  final bool _ownsClient;

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<void> leaveGroup({
    required String accessToken,
    required String groupId,
  }) {
    _validateToken(accessToken);
    _validateId(groupId, 'groupId');
    return _delete(
      path: '/hosted/groups/$groupId/membership',
      accessToken: accessToken,
    );
  }

  Future<void> removeMember({
    required String accessToken,
    required String groupId,
    required String userId,
  }) {
    _validateToken(accessToken);
    _validateId(groupId, 'groupId');
    _validateId(userId, 'userId');
    return _delete(
      path: '/hosted/groups/$groupId/members/$userId',
      accessToken: accessToken,
    );
  }

  Future<HostedOwnershipTransferResult> transferOwnership({
    required String accessToken,
    required String groupId,
    required String newOwnerUserId,
  }) async {
    _validateToken(accessToken);
    _validateId(groupId, 'groupId');
    _validateId(newOwnerUserId, 'newOwnerUserId');
    final http.Response response = await _client.post(
      _baseUri.resolve('/hosted/groups/$groupId/owner'),
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, Object?>{'user_id': newOwnerUserId}),
    );
    final Map<String, Object?> payload = _decodeJsonResponse(response);
    final HostedOwnershipTransferResult result =
        HostedOwnershipTransferResult.fromJson(payload);
    if (result.groupId != groupId || result.ownerUserId != newOwnerUserId) {
      throw const FormatException(
        'Ownership transfer response changed the requested scope.',
      );
    }
    return result;
  }

  Future<void> revokeInvite({
    required String accessToken,
    required String groupId,
  }) {
    _validateToken(accessToken);
    _validateId(groupId, 'groupId');
    return _delete(
      path: '/hosted/groups/$groupId/invite',
      accessToken: accessToken,
    );
  }

  Future<void> _delete({
    required String path,
    required String accessToken,
  }) async {
    final http.Response response = await _client.delete(
      _baseUri.resolve(path),
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    );
    if (response.statusCode == 204) return;
    _decodeJsonResponse(response);
    throw StateError('Expected HTTP 204 for $path.');
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
  if (!_hostedGroupIdPattern.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      label,
      'must be a 32-character lowercase hexadecimal ID',
    );
  }
}

String _requiredId(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String || !_hostedGroupIdPattern.hasMatch(value)) {
    throw FormatException('JSON field $key has an invalid Hosted ID.');
  }
  return value;
}
