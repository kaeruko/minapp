import 'package:http/http.dart' as http;

import '../api.dart';
import '../hosted_api.dart';
import '../hosted_runtime_bridge.dart';

export '../hosted_api.dart';

/// Girls presentation compatibility wrapper.
///
/// Hosted protocol, validation, groups, apps and Runtime behavior live in the
/// neutral [HostedApi]. Girls must not fork the platform contract.
class HostedGirlsApi {
  HostedGirlsApi({required Uri baseUri, http.Client? client})
      : _delegate = HostedApi(baseUri: baseUri, client: client);

  final HostedApi _delegate;

  Uri get baseUri => _delegate.baseUri;
  HostedApiClient get runtimeClient => _delegate.runtimeClient;

  Future<AuthResult> login(String loginId, String password) {
    return _delegate.login(loginId, password);
  }

  Future<HostedLegalBundle> fetchLegal() => _delegate.fetchLegal();

  Future<HostedRegistrationResult> register({
    required String loginId,
    required String password,
    required HostedLegalBundle legal,
  }) {
    return _delegate.register(
      loginId: loginId,
      password: password,
      legal: legal,
    );
  }

  Future<HostedRecoveryResult> recover({
    required String loginId,
    required String recoveryCode,
    required String newPassword,
  }) {
    return _delegate.recover(
      loginId: loginId,
      recoveryCode: recoveryCode,
      newPassword: newPassword,
    );
  }

  Future<HostedEmailStatus> fetchEmailStatus(String accessToken) {
    return _delegate.fetchEmailStatus(accessToken);
  }

  Future<HostedEmailLinkResult> requestEmailLink({
    required String accessToken,
    required String email,
  }) {
    return _delegate.requestEmailLink(
      accessToken: accessToken,
      email: email,
    );
  }

  Future<HostedEmailStatus> verifyEmailLink({
    required String accessToken,
    required String code,
  }) {
    return _delegate.verifyEmailLink(accessToken: accessToken, code: code);
  }

  Future<List<HostedGroup>> listGroups(String accessToken) {
    return _delegate.listGroups(accessToken);
  }

  Future<HostedGroup> createGroup({
    required String accessToken,
    required String name,
  }) {
    return _delegate.createGroup(accessToken: accessToken, name: name);
  }

  Future<HostedGroup> joinGroup({
    required String accessToken,
    required String code,
  }) {
    return _delegate.joinGroup(accessToken: accessToken, code: code);
  }

  Future<List<HostedMember>> listMembers({
    required String accessToken,
    required String groupId,
  }) {
    return _delegate.listMembers(accessToken: accessToken, groupId: groupId);
  }

  Future<HostedInvite> createInvite({
    required String accessToken,
    required String groupId,
  }) {
    return _delegate.createInvite(accessToken: accessToken, groupId: groupId);
  }

  Future<void> revokeInvite({
    required String accessToken,
    required String groupId,
  }) {
    return _delegate.revokeInvite(accessToken: accessToken, groupId: groupId);
  }

  Future<List<HostedBuiltin>> listBuiltins() => _delegate.listBuiltins();

  Future<List<HostedGroupApp>> listGroupApps({
    required String accessToken,
    required String groupId,
  }) {
    return _delegate.listGroupApps(accessToken: accessToken, groupId: groupId);
  }

  Future<HostedGroupApp> installBuiltin({
    required String accessToken,
    required String groupId,
    required String builtinId,
  }) {
    return _delegate.installBuiltin(
      accessToken: accessToken,
      groupId: groupId,
      builtinId: builtinId,
    );
  }

  Future<HostedLaunchGrant> createLaunch({
    required String accessToken,
    required String groupId,
    required String appId,
  }) {
    return _delegate.createLaunch(
      accessToken: accessToken,
      groupId: groupId,
      appId: appId,
    );
  }
}
