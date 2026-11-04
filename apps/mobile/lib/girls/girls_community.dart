import '../hosted_api.dart';
import '../hosted_edition.dart';

const String girlsCommunityGroupId = HostedEditions.girlsCommunityGroupId;
const String girlsCommunityGroupName = HostedEditions.girlsCommunityGroupName;

bool isGirlsCommunityGroup(HostedGroup group) =>
    HostedEditions.girls.community.matches(group);

HostedGroup requireGirlsCommunityGroup(List<HostedGroup> groups) =>
    HostedEditions.girls.community.requireFrom(groups);

List<HostedGroup> girlsPrivateGroups(List<HostedGroup> groups) =>
    HostedEditions.girls.community.privateGroupsFrom(groups);
