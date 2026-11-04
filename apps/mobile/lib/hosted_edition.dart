import 'hosted_api.dart';

/// Product-specific values for a hosted MinApp consumer application.
///
/// Protocol and session behavior must stay edition-neutral. Only identity,
/// presentation labels and the system-managed community differ by edition.
class HostedEdition {
  const HostedEdition({
    required this.id,
    required this.displayName,
    required this.refreshTokenStorageKey,
    required this.community,
  });

  final String id;
  final String displayName;
  final String refreshTokenStorageKey;
  final HostedCommunity community;
}

class HostedCommunity {
  const HostedCommunity({required this.groupId, required this.name});

  final String groupId;
  final String name;

  bool matches(HostedGroup group) => group.groupId == groupId;

  HostedGroup requireFrom(List<HostedGroup> groups) {
    final List<HostedGroup> matchedGroups =
        groups.where(matches).toList(growable: false);
    if (matchedGroups.length != 1) {
      throw StateError(
        'Hosted API must return exactly one $name community for group ID '
        '$groupId; received ${matchedGroups.length}.',
      );
    }
    final HostedGroup community = matchedGroups.single;
    if (community.name != name || community.isOwner) {
      throw StateError(
          'Hosted community metadata is invalid for edition group $groupId.');
    }
    return community;
  }

  List<HostedGroup> privateGroupsFrom(List<HostedGroup> groups) {
    requireFrom(groups);
    return groups
        .where((HostedGroup group) => !matches(group))
        .toList(growable: false);
  }
}

abstract final class HostedEditions {
  static const String girlsCommunityGroupId =
      '00000000000000000000000000000001';
  static const String girlsCommunityGroupName = 'みんなの広場';
  static const String koboCommunityGroupId = '00000000000000000000000000000002';
  static const String koboCommunityGroupName = 'みんなの工房';

  static const HostedEdition girls = HostedEdition(
    id: 'girls',
    displayName: 'みんアプ Girls',
    refreshTokenStorageKey: 'minapp.girls.refresh_token.v1',
    community: HostedCommunity(
      groupId: girlsCommunityGroupId,
      name: girlsCommunityGroupName,
    ),
  );

  static const HostedEdition kobo = HostedEdition(
    id: 'kobo',
    displayName: 'みんアプ工房',
    refreshTokenStorageKey: 'minapp.kobo.refresh_token.v1',
    community: HostedCommunity(
      groupId: koboCommunityGroupId,
      name: koboCommunityGroupName,
    ),
  );
}
