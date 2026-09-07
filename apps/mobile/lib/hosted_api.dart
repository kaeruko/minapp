import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';
import 'hosted_runtime_bridge.dart';

const int maxHostedGroupNameLength = 60;
const int maxHostedEmailLength = 254;

final RegExp _hostedHexIdPattern = RegExp(r'^[0-9a-f]{32}$');
final RegExp _inviteCodePattern = RegExp(
  r'^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}-?[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}-?[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}$',
);
final RegExp _recoveryCodePattern = RegExp(
  r'^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{20}$',
);
final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final RegExp _emailVerificationCodePattern = RegExp(r'^[0-9]{6}$');
final RegExp _builtinIdPattern = RegExp(r'^[a-z0-9][a-z0-9_-]{1,63}$');

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
      userId: _requireHexId(json, 'user_id'),
      loginId: _requiredString(json, 'login_id'),
      recoveryCode: _requiredString(json, 'recovery_code'),
    );
  }
}

class HostedRecoveryResult {
  const HostedRecoveryResult({
    required this.loginId,
    required this.recoveryCode,
  });

  final String loginId;
  final String recoveryCode;

  factory HostedRecoveryResult.fromJson(Map<String, Object?> json) {
    _requireExactFields(
      json,
      const <String>{'login_id', 'recovery_code'},
      'Hosted recovery response',
    );
    return HostedRecoveryResult(
      loginId: _requiredString(json, 'login_id'),
      recoveryCode: _requiredString(json, 'recovery_code'),
    );
  }
}

class HostedEmailStatus {
  const HostedEmailStatus({required this.email, required this.verified});

  final String? email;
  final bool verified;

  factory HostedEmailStatus.fromJson(Map<String, Object?> json) {
    _requireExactFields(
      json,
      const <String>{'email', 'verified'},
      'Hosted email status',
    );
    final String? email = _optionalString(json, 'email');
    final Object? verified = json['verified'];
    if (verified is! bool) {
      throw const FormatException('Hosted email status has invalid verified value.');
    }
    if (verified && email == null) {
      throw const FormatException(
        'Hosted email status cannot be verified without an email.',
      );
    }
    return HostedEmailStatus(email: email, verified: verified);
  }
}

class HostedEmailLinkResult extends HostedEmailStatus {
  const HostedEmailLinkResult({
    required super.email,
    required super.verified,
    required this.codeSent,
    required this.destination,
  });

  final bool codeSent;
  final String? destination;

  factory HostedEmailLinkResult.fromJson(Map<String, Object?> json) {
    _requireExactFields(
      json,
      const <String>{'email', 'verified', 'code_sent', 'destination'},
      'Hosted email link result',
    );
    final Object? verified = json['verified'];
    final Object? codeSent = json['code_sent'];
    if (verified is! bool || codeSent is! bool) {
      throw const FormatException(
        'Hosted email link result has invalid boolean values.',
      );
    }
    return HostedEmailLinkResult(
      email: _requiredString(json, 'email'),
      verified: verified,
      codeSent: codeSent,
      destination: _optionalString(json, 'destination'),
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
    final String role = _requiredString(json, 'role');
    final String status = _requiredString(json, 'status');
    if (role != 'owner' && role != 'member') {
      throw FormatException('Hosted group returned unsupported role: $role.');
    }
    if (status != 'active') {
      throw FormatException('Hosted group returned unsupported status: $status.');
    }
    return HostedGroup(
      groupId: _requireHexId(json, 'group_id'),
      name: _requiredString(json, 'name'),
      role: role,
      status: status,
    );
  }
}

class HostedMember {
  const HostedMember({
    required this.userId,
    required this.loginId,
    required this.role,
    required this.status,
  });

  final String userId;
  final String loginId;
  final String role;
  final String status;

  bool get isOwner => role == 'owner';

  factory HostedMember.fromJson(Map<String, Object?> json) {
    _requireExactFields(
      json,
      const <String>{'user_id', 'login_id', 'role', 'status'},
      'Hosted member',
    );
    final String role = _requiredString(json, 'role');
    final String status = _requiredString(json, 'status');
    if ((role != 'owner' && role != 'member') || status != 'active') {
      throw FormatException('Hosted member returned unsupported role/status: $role/$status.');
    }
    return HostedMember(
      userId: _requireHexId(json, 'user_id'),
      loginId: _requiredString(json, 'login_id'),
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
    final Object? validForSeconds = json['valid_for_seconds'];
    if (validForSeconds is! int || validForSeconds <= 0) {
      throw const FormatException('Hosted invite has invalid valid_for_seconds.');
    }
    return HostedInvite(
      groupId: _requireHexId(json, 'group_id'),
      code: code,
      expiresAt: DateTime.parse(_requiredString(json, 'expires_at')).toUtc(),
      validForSeconds: validForSeconds,
    );
  }
}

class HostedBuiltin {
  const HostedBuiltin({
    required this.builtinId,
    required this.version,
    required this.title,
    required this.assetPath,
  });

  final String builtinId;
  final int version;
  final String title;
  final String assetPath;

  factory HostedBuiltin.fromJson(Map<String, Object?> json) {
    _requireAllowedFields(
      json,
      required: const <String>{'builtin_id', 'version', 'title', 'asset_path'},
      optional: const <String>{'master_data_element_id'},
      context: 'Hosted builtin',
    );
    final Object? version = json['version'];
    if (version is! int || version < 1) {
      throw const FormatException('Hosted builtin has invalid version.');
    }
    return HostedBuiltin(
      builtinId: _requiredString(json, 'builtin_id'),
      version: version,
      title: _requiredString(json, 'title'),
      assetPath: _requiredString(json, 'asset_path'),
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
    required this.ownerUserId,
  });

  final String appId;
  final String groupId;
  final String title;
  final String sourceKind;
  final DateTime createdAt;
  final int? publishedVersion;
  final String? builtinId;
  final String? builtinAssetPath;
  final String ownerUserId;

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
      'owner_user_id',
    };
    final Set<String> actual = json.keys.toSet();
    final Set<String> unexpected = actual.difference(allowed);
    if (unexpected.isNotEmpty) {
      throw FormatException(
        'Hosted group app contained unexpected fields: ${unexpected.join(', ')}.',
      );
    }
    for (final String field in const <String>[
      'app_id',
      'group_id',
      'title',
      'source_kind',
      'created_at',
      'owner_user_id',
    ]) {
      if (!actual.contains(field)) {
        throw FormatException('Hosted group app is missing field: $field.');
      }
    }
    final Object? publishedVersion = json['published_version'];
    if (publishedVersion != null &&
        (publishedVersion is! int || publishedVersion < 1)) {
      throw const FormatException('Hosted group app has invalid published_version.');
    }
    return HostedGroupApp(
      appId: _requireHexId(json, 'app_id'),
      groupId: _requireHexId(json, 'group_id'),
      title: _requiredString(json, 'title'),
      sourceKind: _requiredString(json, 'source_kind'),
      createdAt: DateTime.parse(_requiredString(json, 'created_at')).toUtc(),
      publishedVersion: publishedVersion as int?,
      builtinId: _optionalString(json, 'builtin_id'),
      builtinAssetPath: _optionalString(json, 'builtin_asset_path'),
      ownerUserId: _requireHexId(json, 'owner_user_id'),
    );
  }
}

abstract interface class HostedPlatformApi {
  Uri get baseUri;
  HostedApiClient get runtimeClient;

  Future<AuthResult> login(String loginId, String password);
  Future<HostedLegalBundle> fetchLegal();
  Future<HostedRegistrationResult> register({
    required String loginId,
    required String password,
    required HostedLegalBundle legal,
  });
  Future<HostedRecoveryResult> recover({
    required String loginId,
    required String recoveryCode,
    required String newPassword,
  });
  Future<List<HostedGroup>> listGroups(String accessToken);
  Future<HostedGroup> createGroup({
    required String accessToken,
    required String name,
  });
  Future<HostedGroup> joinGroup({
    required String accessToken,
    required String code,
  });
  Future<List<HostedMember>> listMembers({
    required String accessToken,
    required String groupId,
  });
  Future<HostedInvite> createInvite({
    required String accessToken,
    required String groupId,
  });
  Future<void> revokeInvite({
    required String accessToken,
    required String groupId,
  });
  Future<List<HostedBuiltin>> listBuiltins();
  Future<List<HostedGroupApp>> listGroupApps({
    required String accessToken,
    required String groupId,
  });
  Future<HostedGroupApp> installBuiltin({
    required String accessToken,
    required String groupId,
    required String builtinId,
  });
  Future<HostedLaunchGrant> createLaunch({
    required String accessToken,
    required String groupId,
    required String appId,
  });
}

class HostedApi implements HostedPlatformApi {
  HostedApi({required Uri baseUri, http.Client? client})
      : _baseUri = _validateBaseUri(baseUri),
        _client = client ?? http.Client(),
        _authClient = MinAppApiClient(
          baseUri: _validateBaseUri(baseUri),
          client: client,
        ),
        runtimeClient = HostedApiClient(
          baseUri: _validateBaseUri(baseUri),
          client: client,
        );

  final Uri _baseUri;
  final http.Client _client;
  final MinAppApiClient _authClient;

  @override
  final HostedApiClient runtimeClient;

  @override
  Uri get baseUri => _baseUri;

  @override
  Future<AuthResult> login(String loginId, String password) {
    return _authClient.login(loginId, password);
  }

  @override
  Future<HostedLegalBundle> fetchLegal() async {
    return HostedLegalBundle.fromJson(
      await _jsonRequest(method: 'GET', path: '/hosted/legal'),
    );
  }

  @override
  Future<HostedRegistrationResult> register({
    required String loginId,
    required String password,
    required HostedLegalBundle legal,
  }) async {
    return HostedRegistrationResult.fromJson(
      await _jsonRequest(
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
      ),
    );
  }

  @override
  Future<HostedRecoveryResult> recover({
    required String loginId,
    required String recoveryCode,
    required String newPassword,
  }) async {
    final String normalized = recoveryCode.replaceAll('-', '').trim().toUpperCase();
    if (!_recoveryCodePattern.hasMatch(normalized)) {
      throw ArgumentError.value(
        recoveryCode,
        'recoveryCode',
        'must contain exactly 20 supported recovery-code characters',
      );
    }
    return HostedRecoveryResult.fromJson(
      await _jsonRequest(
        method: 'POST',
        path: '/hosted/recover',
        body: <String, Object?>{
          'login_id': loginId,
          'recovery_code': normalized,
          'new_password': newPassword,
        },
      ),
    );
  }

  @override
  Future<List<HostedGroup>> listGroups(String accessToken) async {
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'GET',
      path: '/hosted/groups',
      accessToken: accessToken,
    );
    return _objectList(payload, 'groups', HostedGroup.fromJson);
  }

  @override
  Future<HostedGroup> createGroup({
    required String accessToken,
    required String name,
  }) async {
    if (name.isEmpty || name != name.trim() || name.length > maxHostedGroupNameLength) {
      throw ArgumentError.value(name, 'name', 'invalid Hosted group name');
    }
    return HostedGroup.fromJson(
      await _jsonRequest(
        method: 'POST',
        path: '/hosted/groups',
        accessToken: accessToken,
        body: <String, Object?>{'name': name},
      ),
    );
  }

  @override
  Future<HostedGroup> joinGroup({
    required String accessToken,
    required String code,
  }) async {
    final String normalized = code.trim().toUpperCase();
    if (!_inviteCodePattern.hasMatch(normalized)) {
      throw ArgumentError.value(code, 'code', 'group ID has an invalid format');
    }
    return HostedGroup.fromJson(
      await _jsonRequest(
        method: 'POST',
        path: '/hosted/groups/join',
        accessToken: accessToken,
        body: <String, Object?>{'code': normalized},
      ),
    );
  }

  @override
  Future<List<HostedMember>> listMembers({
    required String accessToken,
    required String groupId,
  }) async {
    _validateHostedId(groupId, 'groupId');
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'GET',
      path: '/hosted/groups/$groupId/members',
      accessToken: accessToken,
    );
    return _objectList(payload, 'members', HostedMember.fromJson);
  }

  @override
  Future<HostedInvite> createInvite({
    required String accessToken,
    required String groupId,
  }) async {
    _validateHostedId(groupId, 'groupId');
    return HostedInvite.fromJson(
      await _jsonRequest(
        method: 'POST',
        path: '/hosted/groups/$groupId/invite',
        accessToken: accessToken,
        body: const <String, Object?>{},
      ),
    );
  }

  @override
  Future<void> revokeInvite({
    required String accessToken,
    required String groupId,
  }) {
    _validateHostedId(groupId, 'groupId');
    return _emptyRequest(
      method: 'DELETE',
      path: '/hosted/groups/$groupId/invite',
      accessToken: accessToken,
    );
  }

  @override
  Future<List<HostedBuiltin>> listBuiltins() async {
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'GET',
      path: '/hosted/builtins',
    );
    return _objectList(payload, 'builtins', HostedBuiltin.fromJson);
  }

  @override
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
    return _objectList(payload, 'apps', HostedGroupApp.fromJson);
  }

  @override
  Future<HostedGroupApp> installBuiltin({
    required String accessToken,
    required String groupId,
    required String builtinId,
  }) async {
    _validateHostedId(groupId, 'groupId');
    if (!_builtinIdPattern.hasMatch(builtinId)) {
      throw ArgumentError.value(builtinId, 'builtinId', 'invalid builtin ID');
    }
    final HostedGroupApp app = HostedGroupApp.fromJson(
      await _jsonRequest(
        method: 'POST',
        path: '/hosted/groups/$groupId/apps/install',
        accessToken: accessToken,
        body: <String, Object?>{'builtin_id': builtinId},
      ),
    );
    if (app.groupId != groupId || app.sourceKind != 'builtin' || app.builtinId != builtinId) {
      throw const FormatException('Builtin install response changed the requested scope.');
    }
    return app;
  }

  @override
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

  Future<HostedEmailStatus> fetchEmailStatus(String accessToken) async {
    return HostedEmailStatus.fromJson(
      await _jsonRequest(
        method: 'GET',
        path: '/hosted/account/email',
        accessToken: accessToken,
      ),
    );
  }

  Future<HostedEmailLinkResult> requestEmailLink({
    required String accessToken,
    required String email,
  }) async {
    final String normalized = email.trim().toLowerCase();
    if (normalized.length > maxHostedEmailLength || !_emailPattern.hasMatch(normalized)) {
      throw ArgumentError.value(email, 'email', 'must be a valid email address');
    }
    return HostedEmailLinkResult.fromJson(
      await _jsonRequest(
        method: 'POST',
        path: '/hosted/account/email',
        accessToken: accessToken,
        body: <String, Object?>{'email': normalized},
      ),
    );
  }

  Future<HostedEmailStatus> verifyEmailLink({
    required String accessToken,
    required String code,
  }) async {
    final String normalized = code.trim();
    if (!_emailVerificationCodePattern.hasMatch(normalized)) {
      throw ArgumentError.value(code, 'code', 'must be a 6-digit verification code');
    }
    return HostedEmailStatus.fromJson(
      await _jsonRequest(
        method: 'POST',
        path: '/hosted/account/email/verify',
        accessToken: accessToken,
        body: <String, Object?>{'code': normalized},
      ),
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
    if (body != null) headers['Content-Type'] = 'application/json';

    final Uri uri = _baseUri.resolve(path);
    late final http.Response response;
    switch (method) {
      case 'GET':
        if (body != null) throw ArgumentError('GET request must not contain a body.');
        response = await _client.get(uri, headers: headers);
      case 'POST':
        response = await _client.post(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        );
      default:
        throw ArgumentError.value(method, 'method', 'Unsupported HTTP method.');
    }
    return _decodeJsonResponse(response);
  }

  Future<void> _emptyRequest({
    required String method,
    required String path,
    required String accessToken,
  }) async {
    if (method != 'DELETE') {
      throw ArgumentError.value(method, 'method', 'Unsupported empty-response method.');
    }
    if (accessToken.isEmpty) {
      throw ArgumentError.value(accessToken, 'accessToken', 'must not be empty');
    }
    final http.Response response = await _client.delete(
      _baseUri.resolve(path),
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    );
    if (response.statusCode != 204) {
      _decodeJsonResponse(response);
      throw StateError('Expected HTTP 204 for $path.');
    }
  }

  Map<String, Object?> _decodeJsonResponse(http.Response response) {
    final String? contentType = response.headers['content-type'];
    if (contentType == null || !contentType.toLowerCase().startsWith('application/json')) {
      throw FormatException('API returned a non-JSON response (HTTP ${response.statusCode}).');
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('API returned an unexpected JSON payload.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final Object? code = decoded['error'];
      final Object? message = decoded['message'];
      if (code is! String || code.isEmpty || message is! String || message.isEmpty) {
        throw const FormatException('API error response is missing error or message.');
      }
      throw ApiException(
        statusCode: response.statusCode,
        code: code,
        message: message,
      );
    }
    return decoded;
  }
}

List<T> _objectList<T>(
  Map<String, Object?> payload,
  String key,
  T Function(Map<String, Object?> json) parse,
) {
  _requireExactFields(payload, <String>{key}, 'Hosted $key response');
  final Object? raw = payload[key];
  if (raw is! List<Object?>) {
    throw FormatException('Hosted $key response has no $key list.');
  }
  return raw.map((Object? value) {
    if (value is! Map<String, Object?>) {
      throw FormatException('Hosted $key response contains a non-object item.');
    }
    return parse(value);
  }).toList(growable: false);
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
      'Hosted API base URI must be an absolute HTTPS URL without credentials, query, or fragment.',
    );
  }
  return uri;
}

void _validateHostedId(String value, String label) {
  if (!_hostedHexIdPattern.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      label,
      'must be a 32-character lowercase hexadecimal ID',
    );
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
