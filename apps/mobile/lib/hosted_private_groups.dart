import 'api.dart';
import 'hosted_consumer_api.dart';

class HostedPrivateGroupsSnapshot {
  const HostedPrivateGroupsSnapshot({
    required this.community,
    required this.privateGroups,
  });

  final HostedGroup community;
  final List<HostedGroup> privateGroups;
}

class HostedPrivateGroupCreation {
  const HostedPrivateGroupCreation({
    required this.group,
    required this.invite,
  });

  final HostedGroup group;
  final HostedInvite invite;
}

/// Edition-neutral workflow for optional private groups.
///
/// Ordinary play always uses the edition's system community. This service
/// deliberately exposes only the remaining private groups to optional group
/// management UI.
class HostedPrivateGroupsService {
  const HostedPrivateGroupsService({
    required this.api,
    required this.session,
  });

  final HostedConsumerApi api;
  final AuthenticatedSession session;

  Future<HostedPrivateGroupsSnapshot> load() async {
    final List<HostedGroup> groups = await api.listGroups(session.accessToken);
    final HostedGroup community = api.edition.community.requireFrom(groups);
    final List<HostedGroup> privateGroups =
        api.edition.community.privateGroupsFrom(groups);
    return HostedPrivateGroupsSnapshot(
      community: community,
      privateGroups: List<HostedGroup>.unmodifiable(privateGroups),
    );
  }

  Future<HostedPrivateGroupCreation> create({required String name}) async {
    if (name.isEmpty ||
        name != name.trim() ||
        name.length > maxHostedGroupNameLength) {
      throw ArgumentError.value(
        name,
        'name',
        'must be 1-$maxHostedGroupNameLength characters without surrounding whitespace',
      );
    }
    final HostedGroup group = await api.createGroup(
      accessToken: session.accessToken,
      name: name,
    );
    final HostedInvite invite = await api.createInvite(
      accessToken: session.accessToken,
      groupId: group.groupId,
    );
    return HostedPrivateGroupCreation(group: group, invite: invite);
  }

  Future<HostedGroup> join({required String code}) {
    if (code.isEmpty || code != code.trim()) {
      throw ArgumentError.value(
        code,
        'code',
        'must be non-empty without surrounding whitespace',
      );
    }
    return api.joinGroup(accessToken: session.accessToken, code: code);
  }
}
