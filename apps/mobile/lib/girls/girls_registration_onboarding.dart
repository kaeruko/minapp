import '../api.dart';
import '../hosted_api.dart';
import 'girls_community.dart';

/// Verifies the system-managed Girls community after authentication.
///
/// Private groups are optional. The API must always expose exactly one
/// community space and the client never creates a fallback group.
class GirlsRegistrationOnboarding {
  GirlsRegistrationOnboarding(this._api);

  final HostedPlatformApi _api;

  Future<HostedGroup> ensureCommunity(
    AuthenticatedSession session,
  ) async {
    final List<HostedGroup> groups = await _api.listGroups(session.accessToken);
    return requireGirlsCommunityGroup(groups);
  }
}
