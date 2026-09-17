import '../hosted_authoring_contract_api.dart';
import 'girls_app_management_api.dart';
import 'hosted_girls_api.dart';

/// A display-only snapshot owned by one authenticated shell, never persisted.
/// Every page open still revalidates membership and refreshes server data.
class GirlsAppsSnapshot {
  GirlsAppsSnapshot({
    required this.group,
    required this.novelEditorAppId,
    required List<HostedGroup> groups,
    required List<HostedAuthoringAppContract> makers,
    required List<ManagedGirlsApp> apps,
  })  : groups = List.unmodifiable(groups),
        makers = List.unmodifiable(makers),
        apps = List.unmodifiable(apps);

  final HostedGroup group;
  final String novelEditorAppId;
  final List<HostedGroup> groups;
  final List<HostedAuthoringAppContract> makers;
  final List<ManagedGirlsApp> apps;
}

class GirlsAppsCache {
  String? _sessionToken;
  GirlsAppsSnapshot? _snapshot;
  DateTime? _savedAt;

  GirlsAppsSnapshot? read(String sessionToken, String? groupId) {
    if (_sessionToken != sessionToken) {
      clear();
      return null;
    }
    if (_snapshot?.group.groupId != groupId ||
        _savedAt == null ||
        DateTime.now().difference(_savedAt!) > const Duration(minutes: 5)) {
      return null;
    }
    return _snapshot;
  }

  void write(String sessionToken, GirlsAppsSnapshot snapshot) {
    _sessionToken = sessionToken;
    _snapshot = snapshot;
    _savedAt = DateTime.now();
  }

  void clear() {
    _sessionToken = null;
    _snapshot = null;
    _savedAt = null;
  }
}
