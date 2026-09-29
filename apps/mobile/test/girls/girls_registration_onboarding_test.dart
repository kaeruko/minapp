import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/api.dart';
import 'package:minapp_mobile/girls/girls_current_group_store.dart';
import 'package:minapp_mobile/girls/girls_registration_onboarding.dart';
import 'package:minapp_mobile/hosted_api.dart';

void main() {
  const AuthenticatedSession session = AuthenticatedSession(
    accessToken: 'access-token',
    expiresIn: 3600,
  );

  test('replaces a stale selection with the only active group', () async {
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
    final _MemoryCurrentGroupStore currentGroupStore =
        _MemoryCurrentGroupStore('cccccccccccccccccccccccccccccccc');
    final GirlsRegistrationOnboarding onboarding =
        GirlsRegistrationOnboarding(api, currentGroupStore);

    final HostedGroup group = await onboarding.ensureInitialGroup(session);

    expect(group.name, '放課後イラスト部');
    expect(api.listCalls, 1);
    expect(api.createCalls, 0);
    expect(api.lastAccessToken, 'access-token');
    expect(
      currentGroupStore.value,
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    expect(currentGroupStore.saveCount, 1);
  });

  test('keeps a valid selection across multiple memberships', () async {
    final _FakeHostedApi api = _FakeHostedApi(
      groups: const <HostedGroup>[
        HostedGroup(
          groupId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          name: girlsInitialGroupName,
          role: 'owner',
          status: 'active',
        ),
        HostedGroup(
          groupId: 'cccccccccccccccccccccccccccccccc',
          name: '放課後イラスト部',
          role: 'member',
          status: 'active',
        ),
      ],
    );
    final _MemoryCurrentGroupStore currentGroupStore =
        _MemoryCurrentGroupStore('cccccccccccccccccccccccccccccccc');
    final GirlsRegistrationOnboarding onboarding =
        GirlsRegistrationOnboarding(api, currentGroupStore);

    final HostedGroup group = await onboarding.ensureInitialGroup(session);

    expect(group.groupId, 'cccccccccccccccccccccccccccccccc');
    expect(currentGroupStore.saveCount, 0);
  });

  test('stale selection prefers My Group across multiple memberships',
      () async {
    final _FakeHostedApi api = _FakeHostedApi(
      groups: const <HostedGroup>[
        HostedGroup(
          groupId: 'cccccccccccccccccccccccccccccccc',
          name: '放課後イラスト部',
          role: 'member',
          status: 'active',
        ),
        HostedGroup(
          groupId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          name: girlsInitialGroupName,
          role: 'owner',
          status: 'active',
        ),
      ],
    );
    final _MemoryCurrentGroupStore currentGroupStore =
        _MemoryCurrentGroupStore('dddddddddddddddddddddddddddddddd');
    final GirlsRegistrationOnboarding onboarding =
        GirlsRegistrationOnboarding(api, currentGroupStore);

    final HostedGroup group = await onboarding.ensureInitialGroup(session);

    expect(group.groupId, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    expect(
      currentGroupStore.value,
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    expect(currentGroupStore.saveCount, 1);
  });

  test('stale selection falls back to an active membership when no starter exists',
      () async {
    final _FakeHostedApi api = _FakeHostedApi(
      groups: const <HostedGroup>[
        HostedGroup(
          groupId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          name: '写真部',
          role: 'member',
          status: 'active',
        ),
        HostedGroup(
          groupId: 'cccccccccccccccccccccccccccccccc',
          name: '放課後イラスト部',
          role: 'member',
          status: 'active',
        ),
      ],
    );
    final _MemoryCurrentGroupStore currentGroupStore =
        _MemoryCurrentGroupStore('dddddddddddddddddddddddddddddddd');
    final GirlsRegistrationOnboarding onboarding =
        GirlsRegistrationOnboarding(api, currentGroupStore);

    final HostedGroup group = await onboarding.ensureInitialGroup(session);

    expect(group.groupId, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    expect(
      currentGroupStore.value,
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    expect(currentGroupStore.saveCount, 1);
  });

  test('creates the starter group and selects it when the account has no groups',
      () async {
    final _FakeHostedApi api = _FakeHostedApi(groups: const <HostedGroup>[]);
    final _MemoryCurrentGroupStore currentGroupStore =
        _MemoryCurrentGroupStore('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    final GirlsRegistrationOnboarding onboarding =
        GirlsRegistrationOnboarding(api, currentGroupStore);

    final HostedGroup group = await onboarding.ensureInitialGroup(session);

    expect(group.name, girlsInitialGroupName);
    expect(group.isOwner, isTrue);
    expect(api.listCalls, 1);
    expect(api.createCalls, 1);
    expect(api.lastCreatedName, girlsInitialGroupName);
    expect(api.lastAccessToken, 'access-token');
    expect(
      currentGroupStore.value,
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    );
    expect(currentGroupStore.saveCount, 1);
  });

  test('selects a sole legacy starter group without creating another one',
      () async {
    final _FakeHostedApi api = _FakeHostedApi(
      groups: const <HostedGroup>[
        HostedGroup(
          groupId: 'dddddddddddddddddddddddddddddddd',
          name: girlsLegacyInitialGroupName,
          role: 'owner',
          status: 'active',
        ),
      ],
    );
    final _MemoryCurrentGroupStore currentGroupStore =
        _MemoryCurrentGroupStore('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    final GirlsRegistrationOnboarding onboarding =
        GirlsRegistrationOnboarding(api, currentGroupStore);

    final HostedGroup group = await onboarding.ensureInitialGroup(session);

    expect(group.groupId, 'dddddddddddddddddddddddddddddddd');
    expect(api.createCalls, 0);
    expect(
      currentGroupStore.value,
      'dddddddddddddddddddddddddddddddd',
    );
    expect(currentGroupStore.saveCount, 1);
  });

  test('propagates group creation failure without changing selection',
      () async {
    final StateError failure = StateError('create failed');
    final _FakeHostedApi api = _FakeHostedApi(
      groups: const <HostedGroup>[],
      createError: failure,
    );
    final _MemoryCurrentGroupStore currentGroupStore =
        _MemoryCurrentGroupStore('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
    final GirlsRegistrationOnboarding onboarding =
        GirlsRegistrationOnboarding(api, currentGroupStore);

    await expectLater(
      onboarding.ensureInitialGroup(session),
      throwsA(same(failure)),
    );

    expect(api.listCalls, 1);
    expect(api.createCalls, 1);
    expect(
      currentGroupStore.value,
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    expect(currentGroupStore.saveCount, 0);
  });
}

class _MemoryCurrentGroupStore implements GirlsCurrentGroupStore {
  _MemoryCurrentGroupStore(this.value);

  String? value;
  int saveCount = 0;

  @override
  Future<String?> load() async => value;

  @override
  Future<void> save(String groupId) async {
    saveCount += 1;
    value = groupId;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
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
