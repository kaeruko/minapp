import 'dart:async';

import 'package:http/http.dart' as http;

import 'api.dart';
import 'hosted_runtime_bridge.dart';

class HostedRuntimeRefreshException implements Exception {
  const HostedRuntimeRefreshException({
    required this.expiredSessionError,
    required this.refreshError,
  });

  final ApiException expiredSessionError;
  final Object refreshError;

  @override
  String toString() {
    return 'HostedRuntimeRefreshException('
        'expiredSessionError: $expiredSessionError, '
        'refreshError: $refreshError)';
  }
}

class RefreshingHostedApiClient extends HostedApiClient {
  RefreshingHostedApiClient({required super.baseUri, super.client});

  final Map<String, _RuntimeRefreshScope> _runtimeScopes =
      <String, _RuntimeRefreshScope>{};

  @override
  Future<HostedLaunchGrant> createLaunch({
    required String accessToken,
    required String groupId,
    required String appId,
  }) async {
    final HostedLaunchGrant launch = await super.createLaunch(
      accessToken: accessToken,
      groupId: groupId,
      appId: appId,
    );
    final _RuntimeRefreshScope scope = _RuntimeRefreshScope(
      accessToken: accessToken,
      groupId: groupId,
      appId: appId,
      currentToken: launch.runtimeToken,
    );
    _runtimeScopes[launch.runtimeToken] = scope;
    return launch;
  }

  @override
  Future<Object?> getState(String runtimeToken, String key) {
    return _runWithSingleRefresh<Object?>(
      runtimeToken,
      (String token) => super.getState(token, key),
    );
  }

  @override
  Future<Object?> setState(String runtimeToken, String key, Object? value) {
    return _runWithSingleRefresh<Object?>(
      runtimeToken,
      (String token) => super.setState(token, key, value),
    );
  }

  @override
  Future<void> deleteState(String runtimeToken, String key) {
    return _runWithSingleRefresh<void>(
      runtimeToken,
      (String token) => super.deleteState(token, key),
    );
  }

  @override
  Future<Object?> getUserState(String runtimeToken, String key) {
    return _runWithSingleRefresh<Object?>(
      runtimeToken,
      (String token) => super.getUserState(token, key),
    );
  }

  @override
  Future<Object?> setUserState(
    String runtimeToken,
    String key,
    Object? value,
  ) {
    return _runWithSingleRefresh<Object?>(
      runtimeToken,
      (String token) => super.setUserState(token, key, value),
    );
  }

  @override
  Future<void> deleteUserState(String runtimeToken, String key) {
    return _runWithSingleRefresh<void>(
      runtimeToken,
      (String token) => super.deleteUserState(token, key),
    );
  }

  Future<T> _runWithSingleRefresh<T>(
    String suppliedToken,
    Future<T> Function(String token) operation,
  ) async {
    final _RuntimeRefreshScope? scope = _runtimeScopes[suppliedToken];
    if (scope == null) {
      return operation(suppliedToken);
    }

    final String attemptedToken = scope.currentToken;
    try {
      return await operation(attemptedToken);
    } on ApiException catch (error) {
      if (!_isExpiredRuntimeSession(error)) {
        rethrow;
      }
      final String refreshedToken = await _refreshRuntimeSession(
        scope: scope,
        expiredToken: attemptedToken,
        expiredSessionError: error,
      );
      return operation(refreshedToken);
    }
  }

  Future<String> _refreshRuntimeSession({
    required _RuntimeRefreshScope scope,
    required String expiredToken,
    required ApiException expiredSessionError,
  }) async {
    if (scope.currentToken != expiredToken) {
      return scope.currentToken;
    }

    final Future<String>? existingRefresh = scope.refreshFuture;
    if (existingRefresh != null) {
      return existingRefresh;
    }

    final Future<String> refresh = _performRuntimeRefresh(
      scope: scope,
      expiredToken: expiredToken,
      expiredSessionError: expiredSessionError,
    );
    scope.refreshFuture = refresh;
    try {
      return await refresh;
    } finally {
      if (identical(scope.refreshFuture, refresh)) {
        scope.refreshFuture = null;
      }
    }
  }

  Future<String> _performRuntimeRefresh({
    required _RuntimeRefreshScope scope,
    required String expiredToken,
    required ApiException expiredSessionError,
  }) async {
    final HostedLaunchGrant refreshedLaunch;
    try {
      refreshedLaunch = await super.createLaunch(
        accessToken: scope.accessToken,
        groupId: scope.groupId,
        appId: scope.appId,
      );
    } catch (refreshError) {
      throw HostedRuntimeRefreshException(
        expiredSessionError: expiredSessionError,
        refreshError: refreshError,
      );
    }

    if (scope.currentToken != expiredToken) {
      return scope.currentToken;
    }
    scope.currentToken = refreshedLaunch.runtimeToken;
    _runtimeScopes[refreshedLaunch.runtimeToken] = scope;
    return refreshedLaunch.runtimeToken;
  }

  static bool _isExpiredRuntimeSession(ApiException error) {
    return error.statusCode == 404 && error.code == 'runtime_session_not_found';
  }
}

class _RuntimeRefreshScope {
  _RuntimeRefreshScope({
    required this.accessToken,
    required this.groupId,
    required this.appId,
    required this.currentToken,
  });

  final String accessToken;
  final String groupId;
  final String appId;
  String currentToken;
  Future<String>? refreshFuture;
}
