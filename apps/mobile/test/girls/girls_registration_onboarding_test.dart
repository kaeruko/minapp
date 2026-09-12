import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/api.dart';
import 'package:minapp_mobile/girls/girls_registration_onboarding.dart';
import 'package:minapp_mobile/hosted_api.dart';

void main() {
  const AuthenticatedSession session = AuthenticatedSession(
    accessToken: 'access-token',
    expiresIn: 3600,
  );

  test('keeps an existing group without creating another one', () async {
    final _FakeHostedApi api = _FakeHostedApi(
      groups: const <HostedGroup>[
        HostedGroup(
          groupId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          name: '放課後イラスト部',
          role: 'member',
          status: 'active',
        ),
      ],
    );
    final GirlsRegistrationOnboarding onboarding =
        GirlsRegistrationOnboarding(api);

    final HostedGroup group = await onboarding.ensureInitialGroup(session);

    expect(group.name, '放課後イラスト部');
    expect(api.listCalls, 1);
    expect(api.createCalls, 0);
    expect(api.lastAccessToken, 'access-token');
  });

  test('creates the starter group when the account has no groups', () async {
    final _FakeHostedApi api = _FakeHostedApi(groups: const <HostedGroup>[]);
    final GirlsRegistrationOnboarding onboarding =
        GirlsRegistrationOnboarding(api);

    final HostedGroup group = await onboarding.ensureInitialGroup(session);

    expect(group.name, girlsInitialGroupName);
    expect(group.isOwner, isTrue);
    expect(api.listCalls, 1);
    expect(api.createCalls, 1);
    expect(api.lastCreatedName, girlsInitialGroupName);
    expect(api.lastAccessToken, 'access-token');
  });

  test('propagates group creation failure without trying another route',
      () async {
    final StateError failure = StateError('create failed');
    final _FakeHostedApi api = _FakeHostedApi(
      groups: const <HostedGroup>[],
      createError: failure,
    );
    final GirlsRegistrationOnboarding onboarding =
        GirlsRegistrationOnboarding(api);

    await expectLater(
      onboarding.ensureInitialGroup(session),
      throwsA(same(failure)),
    );

    expect(api.listCalls, 1);
    expect(api.createCalls, 1);
  });
}

class _FakeHostedApi extends HostedApi {
  _FakeHostedApi({
    required List<HostedGroup> groups,
    this.createError,
  })  : groups = List<HostedGroup>.of(groups),
        super(baseUri: Uri.parse('https://girls-api.example.com'));

  final List<HostedGroup> groups;
  final Object? createError;
  int listCalls = 0;
  int createCalls = 0;
  String? lastAccessToken;
  String? lastCreatedName;

  @override
  Future<List<HostedGroup>> listGroups(String accessToken) async {
    listCalls += 1;
    lastAccessToken = accessToken;
    return List<HostedGroup>.unmodifiable(groups);
  }

  @override
  Future<HostedGroup> createGroup({
    required String accessToken,
    required String name,
  }) async {
    createCalls += 1;
    lastAccessToken = accessToken;
    lastCreatedName = name;
    final Object? error = createError;
    if (error != null) throw error;
    return HostedGroup(
      groupId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      name: name,
      role: 'owner',
      status: 'active',
    );
  }
}
