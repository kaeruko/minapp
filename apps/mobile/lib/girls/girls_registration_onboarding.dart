import '../api.dart';
import '../hosted_api.dart';
import 'girls_current_group_store.dart';

const String girlsInitialGroupName = 'マイグループ';
const String girlsLegacyInitialGroupName = 'はじめのグループ';

HostedGroup? resolveGirlsCurrentGroup(
  List<HostedGroup> groups, {
  String? storedGroupId,
}) {
  if (groups.isEmpty) return null;

  if (storedGroupId != null) {
    for (final HostedGroup group in groups) {
      if (group.groupId == storedGroupId) {
        return group;
      }
    }
  }

  for (final HostedGroup group in groups) {
    if (group.isOwner && group.name == girlsInitialGroupName) {
      return group;
    }
  }
  for (final HostedGroup group in groups) {
    if (group.isOwner && group.name == girlsLegacyInitialGroupName) {
      return group;
    }
  }

  return groups.first;
}

/// Establishes the minimum group state required by Girls after authentication.
///
/// An empty account receives one ordinary starter group and that group becomes
/// the current group immediately. Existing accounts keep their stored current
/// group when it is still available. If it is missing, Girls selects an owned
/// starter group or, finally, the first active membership. Therefore an account
/// with at least one group never enters the app with no current group.
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

    final String? storedGroupId = await _currentGroupStore.load();
    final HostedGroup? currentGroup = resolveGirlsCurrentGroup(
      groups,
      storedGroupId: storedGroupId,
    );
    if (currentGroup == null) {
      throw StateError(
        'Girls current group resolution returned null for non-empty memberships.',
      );
    }
    if (storedGroupId != currentGroup.groupId) {
      await _currentGroupStore.save(currentGroup.groupId);
    }
    return currentGroup;
  }
}
