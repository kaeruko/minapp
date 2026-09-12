import '../api.dart';
import '../hosted_api.dart';

const String girlsInitialGroupName = 'はじめのグループ';

/// Establishes the minimum group state required by Girls after authentication.
///
/// The operation is intentionally idempotent: an account that already belongs
/// to one or more groups is left untouched. This also makes authentication a
/// safe recovery point if a previous attempt created the group but the client
/// did not observe the response.
class GirlsRegistrationOnboarding {
  GirlsRegistrationOnboarding(this._api);

  final HostedPlatformApi _api;

  Future<HostedGroup> ensureInitialGroup(
    AuthenticatedSession session,
  ) async {
    final List<HostedGroup> groups = await _api.listGroups(session.accessToken);
    if (groups.isNotEmpty) {
      return groups.first;
    }

    return _api.createGroup(
      accessToken: session.accessToken,
      name: girlsInitialGroupName,
    );
  }
}
