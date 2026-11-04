import '../api.dart';
import '../hosted_api.dart';
import '../hosted_edition.dart';

/// Compatibility facade for callers that only need onboarding validation.
class GirlsRegistrationOnboarding {
  GirlsRegistrationOnboarding(this._api);

  final HostedPlatformApi _api;

  Future<HostedGroup> ensureCommunity(AuthenticatedSession session) async {
    final List<HostedGroup> groups = await _api.listGroups(session.accessToken);
    return HostedEditions.girls.community.requireFrom(groups);
  }
}
