import '../api.dart';
import '../hosted_api.dart';
import 'girls_current_group_store.dart';

const String girlsInitialGroupName = 'マイグループ';
const String girlsLegacyInitialGroupName = 'はじめのグループ';

/// Establishes the minimum group state required by Girls after authentication.
///
/// An empty account receives one ordinary starter group and that group becomes
/// the current group immediately. A sole owned starter group is also restored
/// as current so accounts created before current-group persistence was added do
/// not require a manual switch. Other existing memberships are left untouched.
class GirlsRegistrationOnboarding {
  GirlsRegistrationOnboarding(this._api, this._currentGroupStore);

  final HostedPlatformApi _api;
  final GirlsCurrentGroupStore _currentGroupStore;

  Future<HostedGroup> ensureInitialGroup(
    AuthenticatedSession session,
  ) async {
    final List<HostedGroup> groups = await _api.listGroups(session.accessToken);
    if (groups.isEmpty) {
      final HostedGroup created = await _api.createGroup(
        accessToken: session.accessToken,
        name: girlsInitialGroupName,
      );
      await _currentGroupStore.save(created.groupId);
      return created;
    }

    if (groups.length == 1) {
      final HostedGroup onlyGroup = groups.single;
      final bool isStarter = onlyGroup.isOwner &&
          (onlyGroup.name == girlsInitialGroupName ||
              onlyGroup.name == girlsLegacyInitialGroupName);
      if (isStarter) {
        await _currentGroupStore.save(onlyGroup.groupId);
      }
      return onlyGroup;
    }

    return groups.first;
  }
}
