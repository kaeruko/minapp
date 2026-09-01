import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';
import 'hosted_runtime_bridge.dart';

final RegExp _hostedHexIdPattern = RegExp(r'^[0-9a-f]{32}$');
final RegExp _inviteCodePattern = RegExp(
  r'^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}-?[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}-?[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}$',
);

class HostedLegalText {
  const HostedLegalText({
    required this.version,
    required this.title,
    required this.body,
  });

  final String version;
  final String title;
  final String body;

  factory HostedLegalText.fromJson(Map<String, Object?> json) {
    _requireExactFields(
      json,
      const <String>{'version', 'title', 'body'},
      'Hosted legal text',
    );
    return HostedLegalText(
      version: _requiredString(json, 'version'),
      title: _requiredString(json, 'title'),
      body: _requiredString(json, 'body'),
    );
  }
}

class HostedLegalBundle {
  const HostedLegalBundle({
    required this.effectiveDate,
    required this.supportEmail,
    required this.terms,
    required this.privacy,
  });

  final String effectiveDate;
  final String supportEmail;
  final HostedLegalText terms;
  final HostedLegalText privacy;

  factory HostedLegalBundle.fromJson(Map<String, Object?> json) {
    _requireExactFields(
      json,
      const <String>{'effective_date', 'support_email', 'terms', 'privacy'},
      'Hosted legal bundle',
    );
    return HostedLegalBundle(
      effectiveDate: _requiredString(json, 'effective_date'),
      supportEmail: _requiredString(json, 'support_email'),
      terms: HostedLegalText.fromJson(_requiredObject(json, 'terms')),
      privacy: HostedLegalText.fromJson(_requiredObject(json, 'privacy')),
    );
  }
}

class HostedRegistrationResult {
  const HostedRegistrationResult({
    required this.userId,
    required this.loginId,
    required this.recoveryCode,
  });

  final String userId;
  final String loginId;
  final String recoveryCode;

  factory HostedRegistrationResult.fromJson(Map<String, Object?> json) {
    _requireExactFields(
      json,
      const <String>{
        'user_id',
        'login_id',
        'role',
        'status',
        'recovery_code',
        'legal',
      },
      'Hosted registration response',
    );
    final String role = _requiredString(json, 'role');
    final String status = _requiredString(json, 'status');
    if (role != 'user' || status != 'active') {
      throw FormatException(
        'Hosted registration returned unexpected role/status: $role/$status.',
      );
    }
    _requireHexId(json, 'user_id');
    final Map<String, Object?> legal = _requiredObject(json, 'legal');
    _requireExactFields(
      legal,
      const <String>{'terms_version', 'privacy_version', 'accepted_at'},
      'Hosted registration legal receipt',
    );
    _requiredString(legal, 'terms_version');
    _requiredString(legal, 'privacy_version');
    _requiredString(legal, 'accepted_at');
    return HostedRegistrationResult(
      userId: _requiredString(json, 'user_id'),
      loginId: _requiredString(json, 'login_id'),
      recoveryCode: _requiredString(json, 'recovery_code'),
    );
  }
}

class HostedGroup {
  const HostedGroup({
    required this.groupId,
    required this.name,
    required this.role,
    required this.status,
  });

  final String groupId;
  final String name;
  final String role;
  final String status;

  bool get isOwner => role == 'owner';

  factory HostedGroup.fromJson(Map<String, Object?> json) {
    _requireAllowedFields(
      json,
      required: const <String>{'group_id', 'name', 'role', 'status'},
      optional: const <String>{'visibility'},
      context: 'Hosted group',
    );
    final String groupId = _requireHexId(json, 'group_id');
    final String role = _requiredString(json, 'role');
    if (role != 'owner' && role != 'member') {
      throw FormatException('Hosted group returned unsupported role: $role.');
    }
    final String status = _requiredString(json, 'status');
    if (status != 'active') {
      throw FormatException('Hosted group returned unsupported status: $status.');
    }
    return HostedGroup(
      groupId: groupId,
      name: _requiredString(json, 'name'),
      role: role,
      status: status,
    );
  }
}

class HostedInvite {
  const HostedInvite({
    required this.groupId,
    required this.code,
    required this.expiresAt,
    required this.validForSeconds,
  });

  final String groupId;
  final String code;
  final DateTime expiresAt;
  final int validForSeconds;

  factory HostedInvite.fromJson(Map<String, Object?> json) {
    _requireExactFields(
      json,
      const <String>{'group_id', 'code', 'expires_at', 'valid_for_seconds'},
      'Hosted invite',
    );
    final String code = _requiredString(json, 'code');
    if (!_inviteCodePattern.hasMatch(code.toUpperCase())) {
      throw const FormatException('Hosted invite returned an invalid group code.');
    }
    final Object? rawSeconds = json['valid_for_seconds'];
    if (rawSeconds is! int || rawSeconds <= 0) {
      throw const FormatException('Hosted invite has invalid valid_for_seconds.');
    }
    return HostedInvite(
      groupId: _requireHexId(json, 'group_id'),
      code: code,
      expiresAt: DateTime.parse(_requiredString(json, 'expires_at')).toUtc(),
      validForSeconds: rawSeconds,
    );
  }
}

class HostedGroupApp {
  const HostedGroupApp({
    required this.appId,
    required this.groupId,
    required this.title,
    required this.sourceKind,
    required this.createdAt,
    required this.publishedVersion,
    this.builtinId,
    this.builtinAssetPath,
  });

  final String appId;
  final String groupId;
  final String title;
  final String sourceKind;
  final DateTime createdAt;
  final int? publishedVersion;
  final String? builtinId;
  final String? builtinAssetPath;

  bool get isPublished => publishedVersion != null;

  factory HostedGroupApp.fromJson(Map<String, Object?> json) {
    const Set<String> allowed = <String>{
      'app_id',
      'group_id',
      'title',
      'source_kind',
      'created_at',
      'builtin_id',
      'builtin_asset_path',
      'parent_app_id',
      'source_sha256',
      'source_updated_at',
      'published_sha256',
      'published_at',
      'deletion_state',
      'builtin_version',
      'source_revision',
      'published_version',
      'editable',
    };
    final Set<String> unexpected = json.keys.toSet().difference(allowed);
    if (unexpected.isNotEmpty) {
      throw FormatException(
        'Hosted group app contained unexpected fields: ${unexpected.join(', ')}.',
      );
    }
    for (final String field in <String>[
      'app_id',
      'group_id',
      'title',
      'source_kind',
      'created_at',
    ]) {
      if (!json.containsKey(field)) {
        throw FormatException('Hosted group app is missing field: $field.');
      }
    }
    final Object? rawPublished = json['published_version'];
    if (rawPublished != null && (rawPublished is! int || rawPublished < 1)) {
      throw const FormatException('Hosted group app has invalid published_version.');
    }
    return HostedGroupApp(
      appId: _requireHexId(json, 'app_id'),
      groupId: _requireHexId(json, 'group_id'),
      title: _requiredString(json, 'title'),
      sourceKind: _requiredString(json, 'source_kind'),
      createdAt: DateTime.parse(_requiredString(json, 'created_at')).toUtc(),
      publishedVersion: rawPublished as int?,
      builtinId: _optionalString(json, 'builtin_id'),
      builtinAssetPath: _optionalString(json, 'builtin_asset_path'),
    );
  }
}

class HostedGirlsApi {
  factory HostedGirlsApi({required Uri baseUri, http.Client? client}) {
    final Uri validated = _validateBaseUri(baseUri);
    final http.Client sharedClient = client ?? http.Client();
    return HostedGirlsApi._(
      baseUri: validated,
      client: sharedClient,
      authClient: MinAppApiClient(baseUri: validated, client: sharedClient),
      runtimeClient: HostedApiClient(baseUri: validated, client: sharedClient),
    );
  }

  HostedGirlsApi._({
    required Uri baseUri,
    required http.Client client,
    required MinAppApiClient authClient,
    required this.runtimeClient,
  })  : _baseUri = baseUri,
        _client = client,
        _authClient = authClient;

  final Uri _baseUri;
  final http.Client _client;
  final MinAppApiClient _authClient;
  final HostedApiClient runtimeClient;

  Uri get baseUri => _baseUri;

  Future<AuthResult> login(String loginId, String password) {
    return _authClient.login(loginId, password);
  }

  Future<HostedLegalBundle> fetchLegal() async {
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'GET',
      path: '/hosted/legal',
    );
    return HostedLegalBundle.fromJson(payload);
  }

  Future<HostedRegistrationResult> register({
    required String loginId,
    required String password,
    required HostedLegalBundle legal,
  }) async {
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'POST',
      path: '/hosted/register',
      body: <String, Object?>{
        'login_id': loginId,
        'password': password,
        'terms_version': legal.terms.version,
        'privacy_version': legal.privacy.version,
        'terms_accepted': true,
        'privacy_accepted': true,
      },
    );
    return HostedRegistrationResult.fromJson(payload);
  }

  Future<List<HostedGroup>> listGroups(String accessToken) async {
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'GET',
      path: '/hosted/groups',
      accessToken: accessToken,
    );
    _requireExactFields(payload, const <String>{'groups'}, 'Hosted groups response');
    final Object? rawGroups = payload['groups'];
    if (rawGroups is! List<Object?>) {
      throw const FormatException('Hosted groups response has no groups list.');
    }
    return rawGroups.map((Object? raw) {
      if (raw is! Map<String, Object?>) {
        throw const FormatException('Hosted groups response contains a non-object group.');
      }
      return HostedGroup.fromJson(raw);
    }).toList(growable: false);
  }

  Future<HostedGroup> createGroup({
    required String accessToken,
    required String name,
  }) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 80 || trimmed != name) {
      throw ArgumentError.value(
        name,
        'name',
        'must be a trimmed non-empty group name up to 80 characters',
      );
    }
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'POST',
      path: '/hosted/groups',
      accessToken: accessToken,
      body: <String, Object?>{'name': name},
    );
    return HostedGroup.fromJson(payload);
  }

  Future<HostedGroup> joinGroup({
    required String accessToken,
    required String code,
  }) async {
    final String normalized = code.trim().toUpperCase();
    if (!_inviteCodePattern.hasMatch(normalized)) {
      throw ArgumentError.value(code, 'code', 'group ID has an invalid format');
    }
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'POST',
      path: '/hosted/groups/join',
      accessToken: accessToken,
      body: <String, Object?>{'code': normalized},
    );
    return HostedGroup.fromJson(payload);
  }

  Future<HostedInvite> createInvite({
    required String accessToken,
    required String groupId,
  }) async {
    _validateHostedId(groupId, 'groupId');
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'POST',
      path: '/hosted/groups/$groupId/invite',
      accessToken: accessToken,
      body: const <String, Object?>{},
    );
    return HostedInvite.fromJson(payload);
  }

  Future<List<HostedGroupApp>> listGroupApps({
    required String accessToken,
    required String groupId,
  }) async {
    _validateHostedId(groupId, 'groupId');
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'GET',
      path: '/hosted/groups/$groupId/apps',
      accessToken: accessToken,
    );
    _requireExactFields(payload, const <String>{'apps'}, 'Hosted group apps response');
    final Object? rawApps = payload['apps'];
    if (rawApps is! List<Object?>) {
      throw const FormatException('Hosted group apps response has no apps list.');
    }
    return rawApps.map((Object? raw) {
      if (raw is! Map<String, Object?>) {
        throw const FormatException('Hosted group apps response contains a non-object app.');
      }
      return HostedGroupApp.fromJson(raw);
    }).toList(growable: false);
  }

  Future<HostedLaunchGrant> createLaunch({
    required String accessToken,
    required String groupId,
    required String appId,
  }) {
    return runtimeClient.createLaunch(
      accessToken: accessToken,
      groupId: groupId,
      appId: appId,
    );
  }

  Future<Map<String, Object?>> _jsonRequest({
    required String method,
    required String path,
    String? accessToken,
    Map<String, Object?>? body,
  }) async {
    if (!path.startsWith('/')) {
      throw ArgumentError.value(path, 'path', 'API path must start with /.');
    }
    final Map<String, String> headers = <String, String>{'Accept': 'application/json'};
    if (accessToken != null) {
      if (accessToken.isEmpty) {
        throw ArgumentError.value(accessToken, 'accessToken', 'must not be empty');
      }
      headers['Authorization'] = 'Bearer $accessToken';
    }
    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }

    final Uri uri = _baseUri.resolve(path);
    late final http.Response response;
    if (method == 'GET') {
      if (body != null) {
        throw ArgumentError('GET request must not contain a body.');
      }
      response = await _client.get(uri, headers: headers);
    } else if (method == 'POST') {
      response = await _client.post(
        uri,
        headers: headers,
        body: body == null ? null : jsonEncode(body),
      );
    } else {
      throw ArgumentError.value(method, 'method', 'Unsupported HTTP method.');
    }

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
      if (rawCode is! String || rawCode.isEmpty || rawMessage is! String || rawMessage.isEmpty) {
        throw const FormatException('API error response is missing error or message.');
      }
      throw ApiException(
        statusCode: response.statusCode,
        code: rawCode,
        message: rawMessage,
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
        'Hosted API base URI must be an absolute HTTPS URL without credentials, query, or fragment.',
      );
    }
    return uri;
  }
}

void _validateHostedId(String value, String label) {
  if (!_hostedHexIdPattern.hasMatch(value)) {
    throw ArgumentError.value(value, label, 'must be a 32-character lowercase hexadecimal ID');
  }
}

String _requireHexId(Map<String, Object?> json, String key) {
  final String value = _requiredString(json, key);
  if (!_hostedHexIdPattern.hasMatch(value)) {
    throw FormatException('JSON field $key must be a 32-character lowercase hexadecimal ID.');
  }
  return value;
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
    throw FormatException('JSON field $key must be a non-empty string when present.');
  }
  return value;
}

Map<String, Object?> _requiredObject(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! Map<String, Object?>) {
    throw FormatException('JSON field $key must be an object.');
  }
  return value;
}

void _requireExactFields(
  Map<String, Object?> json,
  Set<String> expected,
  String context,
) {
  final Set<String> actual = json.keys.toSet();
  if (actual.length != expected.length || !actual.containsAll(expected)) {
    throw FormatException(
      '$context fields mismatch. Expected ${expected.join(', ')}, got ${actual.join(', ')}.',
    );
  }
}

void _requireAllowedFields(
  Map<String, Object?> json, {
  required Set<String> required,
  required Set<String> optional,
  required String context,
}) {
  final Set<String> actual = json.keys.toSet();
  final Set<String> missing = required.difference(actual);
  final Set<String> unexpected = actual.difference(required.union(optional));
  if (missing.isNotEmpty || unexpected.isNotEmpty) {
    throw FormatException(
      '$context field mismatch. Missing=${missing.join(', ')} unexpected=${unexpected.join(', ')}.',
    );
  }
}
