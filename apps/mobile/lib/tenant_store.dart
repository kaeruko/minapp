import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'directory.dart';
import 'endpoint_validation.dart';

class ConfiguredTenant {
  const ConfiguredTenant({
    required this.tenantId,
    required this.displayName,
    required this.apiBaseUrl,
    required this.apiProtocolVersion,
    required this.configRevision,
    required this.verifiedAt,
    required this.expiresAt,
  });

  final String tenantId;
  final String displayName;
  final Uri apiBaseUrl;
  final int apiProtocolVersion;
  final int configRevision;
  final DateTime verifiedAt;
  final DateTime expiresAt;

  factory ConfiguredTenant.fromVerifiedDescriptor(
    TenantDescriptor descriptor, {
    required DateTime verifiedAt,
  }) {
    final DateTime normalizedVerifiedAt = verifiedAt.toUtc();
    return ConfiguredTenant(
      tenantId: descriptor.tenantId,
      displayName: descriptor.displayName,
      apiBaseUrl: descriptor.apiBaseUrl,
      apiProtocolVersion: descriptor.apiProtocolVersion,
      configRevision: descriptor.configRevision,
      verifiedAt: normalizedVerifiedAt,
      expiresAt: normalizedVerifiedAt.add(
        Duration(seconds: descriptor.validForSeconds),
      ),
    );
  }

  factory ConfiguredTenant.fromJson(Map<String, Object?> json) {
    _requireExactFields(json, const <String>{
      'tenant_id',
      'display_name',
      'api_base_url',
      'api_protocol_version',
      'config_revision',
      'verified_at',
      'expires_at',
    });

    final String tenantId = validateTenantId(_requiredString(json, 'tenant_id'));
    final String displayName = validateDisplayName(
      _requiredString(json, 'display_name'),
    );
    final Uri apiBaseUrl = validatePublicHttpsBaseUri(
      Uri.parse(_requiredString(json, 'api_base_url')),
      argumentName: 'api_base_url',
    );
    final int apiProtocolVersion = _requiredInt(json, 'api_protocol_version');
    if (apiProtocolVersion != supportedTenantApiProtocolVersion) {
      throw FormatException(
        'Unsupported stored api_protocol_version: $apiProtocolVersion',
      );
    }
    final int configRevision = _requiredInt(json, 'config_revision');
    if (configRevision < 1) {
      throw const FormatException('Stored config_revision must be positive.');
    }

    final DateTime verifiedAt = _requiredUtcDateTime(json, 'verified_at');
    final DateTime expiresAt = _requiredUtcDateTime(json, 'expires_at');
    if (!expiresAt.isAfter(verifiedAt)) {
      throw const FormatException('Stored tenant expiry is invalid.');
    }
    final int ttlSeconds = expiresAt.difference(verifiedAt).inSeconds;
    if (ttlSeconds < 1 || ttlSeconds > maxDescriptorValidForSeconds) {
      throw const FormatException('Stored tenant expiry exceeds the supported TTL.');
    }

    return ConfiguredTenant(
      tenantId: tenantId,
      displayName: displayName,
      apiBaseUrl: apiBaseUrl,
      apiProtocolVersion: apiProtocolVersion,
      configRevision: configRevision,
      verifiedAt: verifiedAt,
      expiresAt: expiresAt,
    );
  }

  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now.toUtc());

  Map<String, Object?> toJson() => <String, Object?>{
        'tenant_id': tenantId,
        'display_name': displayName,
        'api_base_url': apiBaseUrl.toString(),
        'api_protocol_version': apiProtocolVersion,
        'config_revision': configRevision,
        'verified_at': verifiedAt.toUtc().toIso8601String(),
        'expires_at': expiresAt.toUtc().toIso8601String(),
      };
}

abstract interface class TenantStore {
  Future<ConfiguredTenant?> load();

  Future<void> save(ConfiguredTenant tenant);

  Future<void> clear();
}

class SharedPreferencesTenantStore implements TenantStore {
  static const String _key = 'minapp.verified_tenant.v1';

  @override
  Future<ConfiguredTenant?> load() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final String? raw = preferences.getString(_key);
    if (raw == null) return null;

    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Stored tenant descriptor is not a JSON object.');
    }
    return ConfiguredTenant.fromJson(decoded);
  }

  @override
  Future<void> save(ConfiguredTenant tenant) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final bool saved = await preferences.setString(_key, jsonEncode(tenant.toJson()));
    if (!saved) {
      throw StateError('Failed to persist the verified tenant descriptor.');
    }
  }

  @override
  Future<void> clear() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final bool removed = await preferences.remove(_key);
    if (!removed && preferences.containsKey(_key)) {
      throw StateError('Failed to remove the verified tenant descriptor.');
    }
  }
}

void _requireExactFields(Map<String, Object?> json, Set<String> expected) {
  final Set<String> actual = json.keys.toSet();
  if (actual.length != expected.length || !actual.containsAll(expected)) {
    throw const FormatException('Stored tenant descriptor schema mismatch.');
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Stored field $key must be a non-empty string.');
  }
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! int) {
    throw FormatException('Stored field $key must be an integer.');
  }
  return value;
}

DateTime _requiredUtcDateTime(Map<String, Object?> json, String key) {
  final String value = _requiredString(json, key);
  final DateTime parsed;
  try {
    parsed = DateTime.parse(value);
  } on FormatException catch (error) {
    throw FormatException('Stored field $key is not an ISO-8601 timestamp.', value, error);
  }
  return parsed.toUtc();
}
