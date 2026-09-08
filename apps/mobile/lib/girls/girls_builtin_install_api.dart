import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';
import 'hosted_girls_api.dart';

const String novelEditorBuiltinId = 'novel-editor';
const String novelPlayerBuiltinId = 'novel-starter';

final RegExp _hostedIdPattern = RegExp(r'^[0-9a-f]{32}$');

class GirlsBuiltinInstallApi {
  GirlsBuiltinInstallApi({required Uri baseUri, http.Client? client})
      : _baseUri = _validateBaseUri(baseUri),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final Uri _baseUri;
  final http.Client _client;
  final bool _ownsClient;

  Future<HostedGroupApp> installNovelEditor({
    required String accessToken,
    required String groupId,
  }) async {
    await ensureNovelPlayer(
      accessToken: accessToken,
      groupId: groupId,
    );
    return _installBuiltin(
      accessToken: accessToken,
      groupId: groupId,
      builtinId: novelEditorBuiltinId,
      label: 'Novel Editor',
    );
  }

  Future<HostedGroupApp> ensureNovelPlayer({
    required String accessToken,
    required String groupId,
  }) async {
    final List<HostedGroupApp> apps = await _listGroupApps(
      accessToken: accessToken,
      groupId: groupId,
    );
    final List<HostedGroupApp> players = apps
        .where(
          (HostedGroupApp app) =>
              app.sourceKind == 'builtin' &&
              app.builtinId == novelPlayerBuiltinId,
        )
        .toList(growable: false);
    if (players.length > 1) {
      throw const FormatException(
        'Group app list contains duplicate Novel Player installations.',
      );
    }
    if (players.length == 1) return players.single;
    return installNovelPlayer(
      accessToken: accessToken,
      groupId: groupId,
    );
  }

  Future<HostedGroupApp> installNovelPlayer({
    required String accessToken,
    required String groupId,
  }) {
    return _installBuiltin(
      accessToken: accessToken,
      groupId: groupId,
      builtinId: novelPlayerBuiltinId,
      label: 'Novel Player',
    );
  }

  Future<List<HostedGroupApp>> _listGroupApps({
    required String accessToken,
    required String groupId,
  }) async {
    _validateRequestScope(accessToken: accessToken, groupId: groupId);
    final Uri uri = _baseUri.resolve('/hosted/groups/$groupId/apps');
    final http.Response response = await _client.get(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    );
    final Map<String, Object?> payload = _decodeJsonObject(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiException(response.statusCode, payload);
    }
    if (payload.length != 1 || !payload.containsKey('apps')) {
      throw const FormatException(
        'Group app list response fields are invalid.',
      );
    }
    final Object? rawApps = payload['apps'];
    if (rawApps is! List<Object?>) {
      throw const FormatException(
        'Group app list response has an invalid apps field.',
      );
    }
    final List<HostedGroupApp> apps = <HostedGroupApp>[];
    for (final Object? rawApp in rawApps) {
      if (rawApp is! Map<String, Object?>) {
        throw const FormatException(
          'Group app list response contains an invalid app entry.',
        );
      }
      final HostedGroupApp app = HostedGroupApp.fromJson(rawApp);
      if (app.groupId != groupId) {
        throw const FormatException(
          'Group app list response changed the requested group scope.',
        );
      }
      apps.add(app);
    }
    return apps;
  }

  Future<HostedGroupApp> _installBuiltin({
    required String accessToken,
    required String groupId,
    required String builtinId,
    required String label,
  }) async {
    _validateRequestScope(accessToken: accessToken, groupId: groupId);

    final Uri uri = _baseUri.resolve('/hosted/groups/$groupId/apps/install');
    final http.Response response = await _client.post(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, Object?>{'builtin_id': builtinId}),
    );

    final Map<String, Object?> payload = _decodeJsonObject(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiException(response.statusCode, payload);
    }

    final HostedGroupApp app = HostedGroupApp.fromJson(payload);
    if (app.groupId != groupId ||
        app.sourceKind != 'builtin' ||
        app.builtinId != builtinId) {
      throw FormatException(
        '$label install response changed the requested app scope.',
      );
    }
    return app;
  }

  void close() {
    if (_ownsClient) _client.close();
  }

  static void _validateRequestScope({
    required String accessToken,
    required String groupId,
  }) {
    if (accessToken.isEmpty) {
      throw ArgumentError.value(accessToken, 'accessToken', 'must not be empty');
    }
    if (!_hostedIdPattern.hasMatch(groupId)) {
      throw ArgumentError.value(
        groupId,
        'groupId',
        'must be a 32-character lowercase hexadecimal ID',
      );
    }
  }

  static Map<String, Object?> _decodeJsonObject(http.Response response) {
    final String? contentType = response.headers['content-type'];
    if (contentType == null ||
        !contentType.toLowerCase().startsWith('application/json')) {
      throw FormatException(
        'Builtin install API returned a non-JSON response (HTTP ${response.statusCode}).',
      );
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException(
        'Builtin install API returned an unexpected JSON payload.',
      );
    }
    return decoded;
  }

  static ApiException _apiException(
    int statusCode,
    Map<String, Object?> payload,
  ) {
    final Set<String> actual = payload.keys.toSet();
    if (actual.length != 2 ||
        !actual.contains('error') ||
        !actual.contains('message')) {
      throw const FormatException(
        'Builtin install API error response fields are invalid.',
      );
    }
    final Object? rawCode = payload['error'];
    final Object? rawMessage = payload['message'];
    if (rawCode is! String ||
        rawCode.isEmpty ||
        rawMessage is! String ||
        rawMessage.isEmpty) {
      throw const FormatException(
        'Builtin install API error response is missing error or message.',
      );
    }
    return ApiException(
      statusCode: statusCode,
      code: rawCode,
      message: rawMessage,
    );
  }

  static Uri _validateBaseUri(Uri uri) {
    if (uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw ArgumentError.value(
        uri,
        'baseUri',
        'must be an HTTPS origin without credentials, path, query, or fragment',
      );
    }
    return uri;
  }
}
