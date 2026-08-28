import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';

const int hostedBridgeVersion = 1;

final RegExp _hostedIdPattern = RegExp(r'^[0-9a-f]{32}$');
final RegExp _runtimeTokenPattern = RegExp(r'^[A-Za-z0-9_-]{32,64}$');
final RegExp _contentTokenPattern = RegExp(r'^[A-Za-z0-9_-]{32,128}$');
final RegExp _contentPathPattern = RegExp(
  r'^/hosted/content/[A-Za-z0-9_-]{32,128}/index\.html$',
);
final RegExp _stateKeyPattern = RegExp(r'^[a-z][a-z0-9_.-]{0,63}$');
final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

class HostedLaunchGrant {
  const HostedLaunchGrant({
    required this.contentUri,
    required this.contentExpiresIn,
    required this.runtimeToken,
    required this.runtimeExpiresIn,
    required this.publishedVersion,
  });

  final Uri contentUri;
  final int contentExpiresIn;
  final String runtimeToken;
  final int runtimeExpiresIn;
  final int publishedVersion;
}

abstract interface class HostedRuntimeTransport {
  Future<Object?> getState(String runtimeToken, String key);

  Future<Object?> setState(String runtimeToken, String key, Object? value);

  Future<void> deleteState(String runtimeToken, String key);
}

class HostedApiClient implements HostedRuntimeTransport {
  HostedApiClient({required Uri baseUri, http.Client? client})
      : _baseUri = _validateBaseUri(baseUri),
        _client = client ?? http.Client();

  final Uri _baseUri;
  final http.Client _client;

  Future<HostedLaunchGrant> createLaunch({
    required String accessToken,
    required String groupId,
    required String appId,
  }) async {
    _validateAccessToken(accessToken);
    _validateHostedId(groupId, 'groupId');
    _validateHostedId(appId, 'appId');

    final Map<String, Object?> payload = await _jsonRequest(
      method: 'POST',
      path: '/hosted/groups/$groupId/apps/$appId/launch-session',
      accessToken: accessToken,
      body: const <String, Object?>{},
    );
    _requireExactFields(
      payload,
      const <String>{
        'content_path',
        'content_expires_in',
        'runtime_token',
        'runtime_expires_in',
        'published_version',
      },
      'Launch response',
    );
    final String contentPath = _requiredString(payload, 'content_path');
    final int contentExpiresIn = _requiredPositiveInt(payload, 'content_expires_in');
    final String runtimeToken = _requiredString(payload, 'runtime_token');
    final int runtimeExpiresIn = _requiredPositiveInt(payload, 'runtime_expires_in');
    final int publishedVersion = _requiredPositiveInt(payload, 'published_version');

    if (!_runtimeTokenPattern.hasMatch(runtimeToken)) {
      throw const FormatException('Launch response has an invalid Runtime token.');
    }
    if (!_contentPathPattern.hasMatch(contentPath)) {
      throw const FormatException('Launch response has an invalid Hosted content path.');
    }
    final Uri contentUri = _baseUri.resolve(contentPath);
    HostedContentNavigationPolicy(contentUri);

    return HostedLaunchGrant(
      contentUri: contentUri,
      contentExpiresIn: contentExpiresIn,
      runtimeToken: runtimeToken,
      runtimeExpiresIn: runtimeExpiresIn,
      publishedVersion: publishedVersion,
    );
  }

  @override
  Future<Object?> getState(String runtimeToken, String key) async {
    _validateRuntimeToken(runtimeToken);
    validateHostedStateKey(key);
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'GET',
      path: '/hosted/runtime/$runtimeToken/state/${Uri.encodeComponent(key)}',
    );
    _validateRuntimeStateResponse(payload, key, 'Runtime get response');
    return payload['value'];
  }

  @override
  Future<Object?> setState(String runtimeToken, String key, Object? value) async {
    _validateRuntimeToken(runtimeToken);
    validateHostedStateKey(key);
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'POST',
      path: '/hosted/runtime/$runtimeToken/state/${Uri.encodeComponent(key)}',
      body: <String, Object?>{'value': value},
    );
    _validateRuntimeStateResponse(payload, key, 'Runtime set response');
    return payload['value'];
  }

  @override
  Future<void> deleteState(String runtimeToken, String key) async {
    _validateRuntimeToken(runtimeToken);
    validateHostedStateKey(key);
    await _emptyRequest(
      method: 'DELETE',
      path: '/hosted/runtime/$runtimeToken/state/${Uri.encodeComponent(key)}',
      expectedStatus: 204,
    );
  }

  Future<Map<String, Object?>> _jsonRequest({
    required String method,
    required String path,
    String? accessToken,
    Map<String, Object?>? body,
  }) async {
    final http.Response response = await _request(
      method: method,
      path: path,
      accessToken: accessToken,
      body: body,
    );
    final Map<String, Object?> decoded = _decodeJsonObject(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiException(response.statusCode, decoded);
    }
    return decoded;
  }

  Future<void> _emptyRequest({
    required String method,
    required String path,
    required int expectedStatus,
  }) async {
    final http.Response response = await _request(method: method, path: path);
    if (response.statusCode == expectedStatus) {
      if (response.body.isNotEmpty) {
        throw FormatException(
          'API returned a body for HTTP $expectedStatus when an empty response was required.',
        );
      }
      return;
    }
    final Map<String, Object?> decoded = _decodeJsonObject(response);
    throw _apiException(response.statusCode, decoded);
  }

  Future<http.Response> _request({
    required String method,
    required String path,
    String? accessToken,
    Map<String, Object?>? body,
  }) async {
    if (!path.startsWith('/')) {
      throw ArgumentError.value(path, 'path', 'API path must start with /.');
    }
    final Uri uri = _baseUri.resolve(path);
    final Map<String, String> headers = <String, String>{'Accept': 'application/json'};
    if (accessToken != null) {
      _validateAccessToken(accessToken);
      headers['Authorization'] = 'Bearer $accessToken';
    }
    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }

    if (method == 'GET') {
      if (body != null) {
        throw ArgumentError('GET request must not contain a body.');
      }
      return _client.get(uri, headers: headers);
    }
    if (method == 'POST') {
      return _client.post(
        uri,
        headers: headers,
        body: body == null ? null : jsonEncode(body),
      );
    }
    if (method == 'DELETE') {
      if (body != null) {
        throw ArgumentError('DELETE request must not contain a body.');
      }
      return _client.delete(uri, headers: headers);
    }
    throw ArgumentError.value(method, 'method', 'Unsupported HTTP method.');
  }

  static Map<String, Object?> _decodeJsonObject(http.Response response) {
    final String? contentType = response.headers['content-type'];
    if (contentType == null ||
        !contentType.toLowerCase().startsWith('application/json')) {
      throw FormatException(
        'API returned a non-JSON response (HTTP ${response.statusCode}).',
      );
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('API returned an unexpected JSON payload.');
    }
    return decoded;
  }

  static void _validateRuntimeStateResponse(
    Map<String, Object?> payload,
    String expectedKey,
    String context,
  ) {
    _requireExactFields(
      payload,
      const <String>{'key', 'value', 'updated_at'},
      context,
    );
    final String returnedKey = _requiredString(payload, 'key');
    if (returnedKey != expectedKey) {
      throw FormatException('$context returned a different state key.');
    }
    _requiredString(payload, 'updated_at');
  }

  static ApiException _apiException(
    int statusCode,
    Map<String, Object?> payload,
  ) {
    _requireExactFields(payload, const <String>{'error', 'message'}, 'API error response');
    final Object? rawCode = payload['error'];
    final Object? rawMessage = payload['message'];
    if (rawCode is! String || rawCode.isEmpty || rawMessage is! String || rawMessage.isEmpty) {
      throw FormatException('API error response is missing error or message.');
    }
    return ApiException(statusCode: statusCode, code: rawCode, message: rawMessage);
  }

  static Uri _validateBaseUri(Uri uri) {
    if (uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw ArgumentError.value(
        uri,
        'baseUri',
        'Hosted API base URI must be an HTTPS origin without credentials, path, query, or fragment.',
      );
    }
    return uri;
  }
}

class HostedContentNavigationPolicy {
  HostedContentNavigationPolicy(Uri contentUri)
      : _contentUri = _validateContentUri(contentUri),
        _allowedPathPrefix = _contentPathPrefix(contentUri);

  final Uri _contentUri;
  final String _allowedPathPrefix;

  bool allows(Uri target) {
    return target.scheme == 'https' &&
        target.host == _contentUri.host &&
        target.port == _contentUri.port &&
        target.userInfo.isEmpty &&
        !_containsTraversalSegment(target) &&
        target.path.startsWith(_allowedPathPrefix);
  }

  static Uri _validateContentUri(Uri uri) {
    if (uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        _containsTraversalSegment(uri)) {
      throw ArgumentError.value(uri, 'contentUri', 'Hosted content URL is invalid.');
    }
    final List<String> segments = uri.pathSegments;
    if (segments.length != 4 ||
        segments[0] != 'hosted' ||
        segments[1] != 'content' ||
        !_contentTokenPattern.hasMatch(segments[2]) ||
        segments[3] != 'index.html') {
      throw ArgumentError.value(uri, 'contentUri', 'Hosted content URL path is invalid.');
    }
    return uri;
  }

  static String _contentPathPrefix(Uri uri) {
    final List<String> segments = uri.pathSegments;
    return '/hosted/content/${segments[2]}/';
  }

  static bool _containsTraversalSegment(Uri uri) {
    return uri.pathSegments.any((String segment) => segment == '.' || segment == '..');
  }
}

class HostedBridgeProtocolException implements Exception {
  const HostedBridgeProtocolException({
    required this.code,
    required this.message,
    this.requestId,
  });

  final String code;
  final String message;
  final String? requestId;

  @override
  String toString() => 'HostedBridgeProtocolException($code, $message)';
}

class HostedBridgeRequest {
  const HostedBridgeRequest({
    required this.id,
    required this.method,
    required this.key,
    required this.hasValue,
    this.value,
  });

  final String id;
  final String method;
  final String key;
  final bool hasValue;
  final Object? value;
}

class HostedBridgeProtocol {
  const HostedBridgeProtocol._();

  static HostedBridgeRequest decodeRequest(String message) {
    final Object? decoded;
    try {
      decoded = jsonDecode(message);
    } on FormatException catch (error) {
      throw HostedBridgeProtocolException(
        code: 'invalid_bridge_request',
        message: 'Bridge request must be valid JSON: ${error.message}',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const HostedBridgeProtocolException(
        code: 'invalid_bridge_request',
        message: 'Bridge request must be a JSON object.',
      );
    }

    final String? requestId = decoded['id'] is String ? decoded['id']! as String : null;
    final Object? rawVersion = decoded['version'];
    if (rawVersion != hostedBridgeVersion) {
      throw HostedBridgeProtocolException(
        code: 'unsupported_bridge_version',
        message: 'Bridge version must be $hostedBridgeVersion.',
        requestId: requestId,
      );
    }
    if (requestId == null || !_requestIdPattern.hasMatch(requestId)) {
      throw const HostedBridgeProtocolException(
        code: 'invalid_bridge_request',
        message: 'Bridge request id is invalid.',
      );
    }

    final Object? rawMethod = decoded['method'];
    if (rawMethod is! String ||
        !const <String>{'state.get', 'state.set', 'state.delete'}.contains(rawMethod)) {
      throw HostedBridgeProtocolException(
        code: 'unsupported_bridge_method',
        message: 'Bridge method is not supported.',
        requestId: requestId,
      );
    }
    final Object? rawKey = decoded['key'];
    if (rawKey is! String) {
      throw HostedBridgeProtocolException(
        code: 'invalid_state_key',
        message: 'State key must be a string.',
        requestId: requestId,
      );
    }
    try {
      validateHostedStateKey(rawKey);
    } on ArgumentError catch (error) {
      throw HostedBridgeProtocolException(
        code: 'invalid_state_key',
        message: error.message?.toString() ?? 'State key is invalid.',
        requestId: requestId,
      );
    }

    final bool hasValue = decoded.containsKey('value');
    final Set<String> expectedFields = rawMethod == 'state.set'
        ? const <String>{'version', 'id', 'method', 'key', 'value'}
        : const <String>{'version', 'id', 'method', 'key'};
    if (decoded.keys.toSet().difference(expectedFields).isNotEmpty ||
        expectedFields.difference(decoded.keys.toSet()).isNotEmpty) {
      throw HostedBridgeProtocolException(
        code: 'invalid_bridge_request',
        message: 'Bridge request fields do not match the method contract.',
        requestId: requestId,
      );
    }

    return HostedBridgeRequest(
      id: requestId,
      method: rawMethod,
      key: rawKey,
      hasValue: hasValue,
      value: decoded['value'],
    );
  }

  static Map<String, Object?> success(String id, Object? result) {
    return <String, Object?>{
      'version': hostedBridgeVersion,
      'id': id,
      'ok': true,
      'result': result,
    };
  }

  static Map<String, Object?> error({
    required String id,
    required int status,
    required String code,
    required String message,
  }) {
    return <String, Object?>{
      'version': hostedBridgeVersion,
      'id': id,
      'ok': false,
      'error': <String, Object?>{
        'status': status,
        'code': code,
        'message': message,
      },
    };
  }

  static const String bootstrapJavaScript = r'''
(() => {
  'use strict';
  const VERSION = 1;
  const channel = window.MinAppNativeBridge;
  if (!channel || typeof channel.postMessage !== 'function') {
    throw new Error('MinApp native bridge is unavailable.');
  }
  if (window.minapp && window.minapp.version === VERSION &&
      typeof window.__minappBridgeReceive === 'function') {
    window.dispatchEvent(new Event('minappready'));
    return;
  }

  const pending = new Map();
  let nextId = 1;

  class MinAppError extends Error {
    constructor(status, code, message) {
      super(message);
      this.name = 'MinAppError';
      this.status = status;
      this.code = code;
    }
  }

  const send = (method, key, hasValue, value) => new Promise((resolve, reject) => {
    const id = String(nextId++);
    const request = { version: VERSION, id, method, key };
    if (hasValue) request.value = value;
    pending.set(id, { resolve, reject });
    try {
      channel.postMessage(JSON.stringify(request));
    } catch (error) {
      pending.delete(id);
      reject(new MinAppError(0, 'bridge_unavailable', String(error)));
    }
  });

  Object.defineProperty(window, '__minappBridgeReceive', {
    configurable: true,
    value: (response) => {
      if (!response || response.version !== VERSION || typeof response.id !== 'string') {
        throw new Error('Invalid MinApp bridge response.');
      }
      const waiter = pending.get(response.id);
      if (!waiter) return;
      pending.delete(response.id);
      if (response.ok === true) {
        waiter.resolve(response.result);
        return;
      }
      const error = response.error;
      if (!error || typeof error.status !== 'number' ||
          typeof error.code !== 'string' || typeof error.message !== 'string') {
        waiter.reject(new MinAppError(0, 'invalid_bridge_response', 'Invalid MinApp bridge error response.'));
        return;
      }
      waiter.reject(new MinAppError(error.status, error.code, error.message));
    },
  });

  const state = Object.freeze({
    get: (key) => send('state.get', key, false, undefined),
    set: (key, value) => send('state.set', key, true, value),
    delete: (key) => send('state.delete', key, false, undefined),
  });
  Object.defineProperty(window, 'minapp', {
    configurable: true,
    value: Object.freeze({ version: VERSION, state }),
  });
  window.dispatchEvent(new Event('minappready'));
})();
''';
}

class HostedBridgeSession {
  HostedBridgeSession({
    required HostedRuntimeTransport transport,
    required String runtimeToken,
  })  : _transport = transport,
        _runtimeToken = _validatedRuntimeToken(runtimeToken);

  final HostedRuntimeTransport _transport;
  final String _runtimeToken;
  final Set<String> _inFlightRequestIds = <String>{};

  Future<Map<String, Object?>> handleMessage(String message) async {
    final HostedBridgeRequest request;
    try {
      request = HostedBridgeProtocol.decodeRequest(message);
    } on HostedBridgeProtocolException catch (error) {
      return HostedBridgeProtocol.error(
        id: error.requestId ?? '',
        status: 400,
        code: error.code,
        message: error.message,
      );
    }

    if (!_inFlightRequestIds.add(request.id)) {
      return HostedBridgeProtocol.error(
        id: request.id,
        status: 409,
        code: 'duplicate_request_id',
        message: 'A bridge request with this id is already in flight.',
      );
    }

    try {
      final Object? result;
      if (request.method == 'state.get') {
        result = await _transport.getState(_runtimeToken, request.key);
      } else if (request.method == 'state.set') {
        if (!request.hasValue) {
          throw StateError('state.set request lost its required value after validation.');
        }
        result = await _transport.setState(_runtimeToken, request.key, request.value);
      } else if (request.method == 'state.delete') {
        await _transport.deleteState(_runtimeToken, request.key);
        result = null;
      } else {
        throw StateError('Validated bridge request has an unsupported method.');
      }
      return HostedBridgeProtocol.success(request.id, result);
    } on ApiException catch (error) {
      return HostedBridgeProtocol.error(
        id: request.id,
        status: error.statusCode,
        code: error.code,
        message: error.message,
      );
    } finally {
      _inFlightRequestIds.remove(request.id);
    }
  }
}

class HostedBridgeDocumentInjector {
  int _finishedDocumentCount = 0;

  int get finishedDocumentCount => _finishedDocumentCount;

  String scriptForFinishedDocument() {
    _finishedDocumentCount += 1;
    return HostedBridgeProtocol.bootstrapJavaScript;
  }
}

void validateHostedStateKey(String key) {
  if (!_stateKeyPattern.hasMatch(key)) {
    throw ArgumentError.value(
      key,
      'key',
      'must start with a lowercase letter and contain only lowercase letters, digits, _, -, or .',
    );
  }
}

void _validateHostedId(String value, String name) {
  if (!_hostedIdPattern.hasMatch(value)) {
    throw ArgumentError.value(value, name, 'must be a 32-character lowercase hexadecimal id');
  }
}

void _validateAccessToken(String accessToken) {
  if (accessToken.isEmpty) {
    throw ArgumentError.value(accessToken, 'accessToken', 'must not be empty');
  }
}

void _validateRuntimeToken(String token) {
  if (!_runtimeTokenPattern.hasMatch(token)) {
    throw ArgumentError.value(token, 'runtimeToken', 'has an invalid format');
  }
}

String _validatedRuntimeToken(String token) {
  _validateRuntimeToken(token);
  return token;
}

String _requiredString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('JSON field $key must be a non-empty string.');
  }
  return value;
}

int _requiredPositiveInt(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! int || value <= 0) {
    throw FormatException('JSON field $key must be a positive integer.');
  }
  return value;
}

void _requireExactFields(
  Map<String, Object?> json,
  Set<String> expected,
  String context,
) {
  final Set<String> actual = json.keys.toSet();
  if (actual.length != expected.length ||
      actual.difference(expected).isNotEmpty ||
      expected.difference(actual).isNotEmpty) {
    throw FormatException('$context fields do not match the protocol contract.');
  }
}
