import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/api.dart';
import 'package:minapp_mobile/girls/girls_community.dart';
import 'package:minapp_mobile/girls/girls_registration_onboarding.dart';
import 'package:minapp_mobile/hosted_api.dart';

void main() {
  const AuthenticatedSession session = AuthenticatedSession(
    accessToken: 'access-token',
    expiresIn: 3600,
  );

  test('requires the system community and keeps private groups optional',
      () async {
    final _FakeHostedApi api = _FakeHostedApi(
      groups: const <HostedGroup>[
        HostedGroup(
          groupId: girlsCommunityGroupId,
          name: girlsCommunityGroupName,
          role: 'member',
          status: 'active',
        ),
        HostedGroup(
          groupId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          name: '放課後イラスト部',
          role: 'owner',
          status: 'active',
        ),
      ],
    );

    final HostedGroup community =
        await GirlsRegistrationOnboarding(api).ensureCommunity(session);

    expect(community.groupId, girlsCommunityGroupId);
    expect(api.listCalls, 1);
    expect(api.lastAccessToken, 'access-token');
  });

  test('does not create a fallback when the community is missing', () async {
    final _FakeHostedApi api = _FakeHostedApi(groups: const <HostedGroup>[]);

    await expectLater(
      GirlsRegistrationOnboarding(api).ensureCommunity(session),
      throwsA(isA<StateError>()),
    );
  });

  test('rejects duplicate community descriptors', () async {
    const HostedGroup community = HostedGroup(
      groupId: girlsCommunityGroupId,
      name: girlsCommunityGroupName,
      role: 'member',
      status: 'active',
    );
    final _FakeHostedApi api = _FakeHostedApi(
      groups: const <HostedGroup>[community, community],
    );

    await expectLater(
      GirlsRegistrationOnboarding(api).ensureCommunity(session),
      throwsA(isA<StateError>()),
    );
  });

  test('rejects mutable owner metadata for the community', () async {
    final _FakeHostedApi api = _FakeHostedApi(
      groups: const <HostedGroup>[
        HostedGroup(
          groupId: girlsCommunityGroupId,
          name: girlsCommunityGroupName,
          role: 'owner',
          status: 'active',
        ),
      ],
    );

    await expectLater(
      GirlsRegistrationOnboarding(api).ensureCommunity(session),
      throwsA(isA<StateError>()),
    );
  });
}

class _FakeHostedApi extends HostedApi {
  _FakeHostedApi({required this.groups})
      : super(baseUri: Uri.parse('https://girls-api.example.com'));

  final List<HostedGroup> groups;
  int listCalls = 0;
  String? lastAccessToken;

  @override
  Future<List<HostedGroup>> listGroups(String accessToken) async {
    listCalls += 1;
    lastAccessToken = accessToken;
    return List<HostedGroup>.unmodifiable(groups);
  }
}
