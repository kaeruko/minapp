import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/hosted_api.dart';
import 'package:minapp_mobile/hosted_edition.dart';

void main() {
  test('Girls and Kobo have isolated identity and community values', () {
    expect(HostedEditions.girls.id, 'girls');
    expect(HostedEditions.kobo.id, 'kobo');
    expect(
      HostedEditions.girls.refreshTokenStorageKey,
      isNot(HostedEditions.kobo.refreshTokenStorageKey),
    );
    expect(
      HostedEditions.girls.community.groupId,
      isNot(HostedEditions.kobo.community.groupId),
    );
  });

  test('community policy separates optional private groups', () {
    final HostedCommunity policy = HostedEditions.kobo.community;
    final HostedGroup community = HostedGroup(
      groupId: policy.groupId,
      name: policy.name,
      role: 'member',
      status: 'active',
    );
    const HostedGroup privateGroup = HostedGroup(
      groupId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      name: '仲間の工房',
      role: 'owner',
      status: 'active',
    );

    expect(policy.requireFrom(<HostedGroup>[community]), same(community));
    expect(
      policy.privateGroupsFrom(<HostedGroup>[community, privateGroup]),
      <HostedGroup>[privateGroup],
    );
  });

  test('community policy fails fast instead of choosing a fallback', () {
    expect(
      () => HostedEditions.kobo.community.requireFrom(const <HostedGroup>[]),
      throwsStateError,
    );
  });
}
