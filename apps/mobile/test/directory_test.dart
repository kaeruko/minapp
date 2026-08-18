import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/directory.dart';
import 'package:minapp_mobile/endpoint_validation.dart';
import 'package:minapp_mobile/tenant_store.dart';

Map<String, Object?> _descriptorJson() => <String, Object?>{
      'schema_version': 1,
      'tenant_id': '35cbf2c880cf41dab580d47b25ba7f0e',
      'display_name': 'みんアプ 開発教室',
      'api_base_url': 'https://tsacejbwej.execute-api.us-west-2.amazonaws.com',
      'api_protocol_version': 1,
      'config_revision': 1,
      'valid_for_seconds': 86400,
    };

void main() {
  test('accepts the Phase 6 v1 tenant descriptor', () {
    final TenantDescriptor descriptor = TenantDescriptor.fromJson(
      _descriptorJson(),
    );

    expect(descriptor.tenantId, '35cbf2c880cf41dab580d47b25ba7f0e');
    expect(
      descriptor.apiBaseUrl,
      Uri.parse('https://tsacejbwej.execute-api.us-west-2.amazonaws.com'),
    );
    expect(descriptor.validForSeconds, 86400);
  });

  test('rejects unknown descriptor fields instead of guessing', () {
    final Map<String, Object?> json = _descriptorJson();
    json['unexpected'] = true;

    expect(
      () => TenantDescriptor.fromJson(json),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects descriptor TTL above the v1 client maximum', () {
    final Map<String, Object?> json = _descriptorJson();
    json['valid_for_seconds'] = 86401;

    expect(
      () => TenantDescriptor.fromJson(json),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects IP literal and local tenant endpoints', () {
    expect(
      () => validatePublicHttpsBaseUri(
        Uri.parse('https://127.0.0.1'),
        argumentName: 'api_base_url',
      ),
      throwsArgumentError,
    );
    expect(
      () => validatePublicHttpsBaseUri(
        Uri.parse('https://minapp.local'),
        argumentName: 'api_base_url',
      ),
      throwsArgumentError,
    );
  });

  test('stored tenant contains only the approved persisted fields', () {
    final TenantDescriptor descriptor = TenantDescriptor.fromJson(
      _descriptorJson(),
    );
    final ConfiguredTenant configured = ConfiguredTenant.fromVerifiedDescriptor(
      descriptor,
      verifiedAt: DateTime.utc(2026, 8, 18, 1),
    );

    expect(configured.toJson().keys.toSet(), <String>{
      'tenant_id',
      'display_name',
      'api_base_url',
      'api_protocol_version',
      'config_revision',
      'verified_at',
      'expires_at',
    });
    expect(configured.expiresAt, DateTime.utc(2026, 8, 19, 1));
  });
}
