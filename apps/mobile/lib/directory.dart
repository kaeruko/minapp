import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';
import 'endpoint_validation.dart';

const int supportedDirectorySchemaVersion = 1;
const int supportedTenantApiProtocolVersion = 1;
const int maxDescriptorValidForSeconds = 86400;

class TenantDescriptor {
  const TenantDescriptor({
    required this.tenantId,
    required this.displayName,
    required this.apiBaseUrl,
    required this.apiProtocolVersion,
    required this.configRevision,
    required this.validForSeconds,
  });

  final String tenantId;
  final String displayName;
  final Uri apiBaseUrl;
  final int apiProtocolVersion;
  final int configRevision;
  final int validForSeconds;

  factory TenantDescriptor.fromJson(Map<String, Object?> json) {
    _requireExactFields(json, const <String>{
      'schema_version',
      'tenant_id',
      'display_name',
      'api_base_url',
      'api_protocol_version',
      'config_revision',
      'valid_for_seconds',
    });

    final int schemaVersion = _requiredInt(json, 'schema_version');
    if (schemaVersion != supportedDirectorySchemaVersion) {
      throw FormatException('Unsupported Directory schema_version: $schemaVersion');
    }

    final String tenantId = validateTenantId(_requiredString(json, 'tenant_id'));
    final String displayName = validateDisplayName(_requiredString(json, 'display_name'));
    final Uri apiBaseUrl = validatePublicHttpsBaseUri(
      Uri.parse(_requiredString(json, 'api_base_url')),
      argumentName: 'api_base_url',
    );
    final int apiProtocolVersion = _requiredInt(json, 'api_protocol_version');
    if (apiProtocolVersion != supportedTenantApiProtocolVersion) {
      throw FormatException(
        'Unsupported tenant api_protocol_version: $apiProtocolVersion',
      );
    }
    final int configRevision = _requiredInt(json, 'config_revision');
    if (configRevision < 1) {
      throw const FormatException('config_revision must be positive.');
    }
    final int validForSeconds = _requiredInt(json, 'valid_for_seconds');
    if (validForSeconds < 1 || validForSeconds > maxDescriptorValidForSeconds) {
      throw const FormatException('valid_for_seconds is outside the supported range.');
    }

    return TenantDescriptor(
      tenantId: tenantId,
      displayName: displayName,
      apiBaseUrl: apiBaseUrl,
      apiProtocolVersion: apiProtocolVersion,
      configRevision: configRevision,
      validForSeconds: validForSeconds,
    );
  }
}

abstract interface class MinAppDirectory {
  Future<TenantDescriptor> resolveClassroom(String classroomCode);

  Future<TenantDescriptor> refreshTenant(String tenantId);

  Future<void> verifyTenantEndpoint(TenantDescriptor descriptor);
}

class MinAppDirectoryClient implements MinAppDirectory {
  MinAppDirectoryClient({required Uri baseUri, http.Client? client})
      : _baseUri = validatePublicHttpsBaseUri(
          baseUri,
          argumentName: 'directoryBaseUri',
        ),
        _client = client ?? http.Client();

  final Uri _baseUri;
  final http.Client _client;

  @override
  Future<TenantDescriptor> resolveClassroom(String classroomCode) async {
    if (classroomCode.isEmpty) {
      throw ArgumentError.value(classroomCode, 'classroomCode', 'must not be empty');
    }
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'POST',
      uri: _baseUri.resolve('/v1/classrooms/resolve'),
      body: <String, Object?>{'code': classroomCode},
    );
    return TenantDescriptor.fromJson(payload);
  }

  @override
  Future<TenantDescriptor> refreshTenant(String tenantId) async {
    final String validatedTenantId = validateTenantId(tenantId);
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'GET',
      uri: _baseUri.resolve('/v1/tenants/$validatedTenantId'),
    );
    final TenantDescriptor descriptor = TenantDescriptor.fromJson(payload);
    if (descriptor.tenantId != validatedTenantId) {
      throw const FormatException('Directory returned a different tenant_id.');
    }
    return descriptor;
  }

  @override
  Future<void> verifyTenantEndpoint(TenantDescriptor descriptor) async {
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'GET',
      uri: descriptor.apiBaseUrl.resolve('/tenant-info'),
    );
    _requireExactFields(payload, const <String>{
      'service',
      'tenant_id',
      'api_protocol_version',
      'environment',
    });
    if (_requiredString(payload, 'service') != 'minapp-tenant-api') {
      throw const FormatException('tenant-info service mismatch.');
    }
    if (validateTenantId(_requiredString(payload, 'tenant_id')) !=
        descriptor.tenantId) {
      throw const FormatException('tenant-info tenant_id mismatch.');
    }
    if (_requiredInt(payload, 'api_protocol_version') !=
        descriptor.apiProtocolVersion) {
      throw const FormatException('tenant-info api_protocol_version mismatch.');
    }
    if (_requiredString(payload, 'environment').isEmpty) {
      throw const FormatException('tenant-info environment is invalid.');
    }
  }

  Future<Map<String, Object?>> _jsonRequest({
    required String method,
    required Uri uri,
    Map<String, Object?>? body,
  }) async {
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
    };
    if (body != null) headers['Content-Type'] = 'application/json';

    late final http.Response response;
    if (method == 'GET') {
      if (body != null) throw ArgumentError('GET request must not contain a body.');
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
      throw ApiException(
        statusCode: response.statusCode,
        code: decoded['error'] is String ? decoded['error']! as String : 'api_error',
        message: decoded['message'] is String
            ? decoded['message']! as String
            : 'API request failed with HTTP ${response.statusCode}.',
      );
    }
    return decoded;
  }
}

String validateTenantId(String value) {
  if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(value)) {
    throw const FormatException(
      'tenant_id must be exactly 32 lowercase hexadecimal characters.',
    );
  }
  return value;
}

String validateDisplayName(String value) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty ||
      trimmed.length > 120 ||
      trimmed.codeUnits.any((int unit) => unit < 0x20)) {
    throw const FormatException('display_name is invalid.');
  }
  return trimmed;
}

void _requireExactFields(Map<String, Object?> json, Set<String> expected) {
  final Set<String> actual = json.keys.toSet();
  if (actual.length != expected.length || !actual.containsAll(expected)) {
    throw const FormatException('JSON object schema mismatch.');
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('JSON field $key must be a non-empty string.');
  }
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! int) {
    throw FormatException('JSON field $key must be an integer.');
  }
  return value;
}
