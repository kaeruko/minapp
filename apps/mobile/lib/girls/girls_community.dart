import '../hosted_api.dart';

const String girlsCommunityGroupId = '00000000000000000000000000000001';
const String girlsCommunityGroupName = 'みんなの広場';

bool isGirlsCommunityGroup(HostedGroup group) {
  return group.groupId == girlsCommunityGroupId;
}

HostedGroup requireGirlsCommunityGroup(List<HostedGroup> groups) {
  final List<HostedGroup> matches = groups
      .where(isGirlsCommunityGroup)
      .toList(growable: false);
  if (matches.length != 1) {
    throw StateError(
      'Girls API must return exactly one community space; '
      'received ${matches.length}.',
    );
  }
  final HostedGroup community = matches.single;
  if (community.name != girlsCommunityGroupName || community.isOwner) {
    throw StateError('Girls community space metadata is invalid.');
  }
  return community;
}

List<HostedGroup> girlsPrivateGroups(List<HostedGroup> groups) {
  requireGirlsCommunityGroup(groups);
  return groups
      .where((HostedGroup group) => !isGirlsCommunityGroup(group))
      .toList(growable: false);
}
