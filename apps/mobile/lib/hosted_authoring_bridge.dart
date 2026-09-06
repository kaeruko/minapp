import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';

const int hostedAuthoringBridgeVersion = 1;

final RegExp _authoringIdPattern = RegExp(r'^[0-9a-f]{32}$');
final RegExp _authoringTokenPattern = RegExp(r'^[A-Za-z0-9_-]{32,64}$');
final RegExp _authoringRequestIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

class HostedAuthoringGrant {
  const HostedAuthoringGrant({
    required this.token,
    required this.expiresIn,
    required this.contentId,
    required this.contentFormat,
    required this.editorAppId,
    required this.allowedOperations,
  });

  final String token;
  final int expiresIn;
  final String contentId;
  final String contentFormat;
  final String editorAppId;
  final List<String> allowedOperations;
}

abstract interface class HostedAuthoringTransport {
  Future<Map<String, Object?>> loadProject(String authoringToken);

  Future<Map<String, Object?>> saveDocument(
    String authoringToken, {
    required int expectedRevision,
    required Map<String, Object?> document,
  });
}

class HostedAuthoringApiClient implements HostedAuthoringTransport {
  HostedAuthoringApiClient({required Uri baseUri, http.Client? client})
      : _baseUri = _validateBaseUri(baseUri),
        _client = client ?? http.Client();

  final Uri _baseUri;
  final http.Client _client;

  Future<HostedAuthoringGrant> createSession({
    required String accessToken,
    required String contentId,
    required String editorAppId,
  }) async {
    _validateAccessToken(accessToken);
    _validateId(contentId, 'contentId');
    _validateId(editorAppId, 'editorAppId');
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'POST',
      path: '/hosted/authoring/projects/$contentId/session',
      accessToken: accessToken,
      body: <String, Object?>{'editor_app_id': editorAppId},
    );
    _requireExactFields(
      payload,
      const <String>{
        'token',
        'expires_in',
        'content_id',
        'content_format',
        'editor_app_id',
        'allowed_operations',
      },
      'Authoring session response',
    );
    final String token = _requiredString(payload, 'token');
    _validateAuthoringToken(token);
    final String returnedContentId = _requiredString(payload, 'content_id');
    final String returnedEditorAppId = _requiredString(payload, 'editor_app_id');
    if (returnedContentId != contentId || returnedEditorAppId != editorAppId) {
      throw const FormatException('Authoring session response changed the requested scope.');
    }
    final List<String> allowedOperations = _requiredStringList(
      payload,
      'allowed_operations',
    );
    return HostedAuthoringGrant(
      token: token,
      expiresIn: _requiredPositiveInt(payload, 'expires_in'),
      contentId: returnedContentId,
      contentFormat: _requiredString(payload, 'content_format'),
      editorAppId: returnedEditorAppId,
      allowedOperations: List<String>.unmodifiable(allowedOperations),
    );
  }

  @override
  Future<Map<String, Object?>> loadProject(String authoringToken) async {
    _validateAuthoringToken(authoringToken);
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'GET',
      path: '/hosted/authoring/session/$authoringToken',
    );
    _validateProjectPayload(payload, includeDocument: true);
    return payload;
  }

  @override
  Future<Map<String, Object?>> saveDocument(
    String authoringToken, {
    required int expectedRevision,
    required Map<String, Object?> document,
  }) async {
    _validateAuthoringToken(authoringToken);
    if (expectedRevision < 1) {
      throw ArgumentError.value(
        expectedRevision,
        'expectedRevision',
        'must be a positive integer',
      );
    }
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'POST',
      path: '/hosted/authoring/session/$authoringToken/document',
      body: <String, Object?>{
        'expected_revision': expectedRevision,
        'document': document,
      },
    );
    _validateProjectPayload(payload, includeDocument: false);
    return payload;
  }

  Future<Map<String, Object?>> _jsonRequest({
    required String method,
    required String path,
    String? accessToken,
    Map<String, Object?>? body,
  }) async {
    if (!path.startsWith('/')) {
      throw ArgumentError.value(path, 'path', 'must start with /.');
    }
    final Uri uri = _baseUri.resolve(path);
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
    };
    if (accessToken != null) {
      _validateAccessToken(accessToken);
      headers['Authorization'] = 'Bearer $accessToken';
    }
    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }

    final http.Response response;
    if (method == 'GET') {
      if (body != null) throw ArgumentError('GET request must not contain a body.');
      response = await _client.get(uri, headers: headers);
    } else if (method == 'POST') {
      response = await _client.post(
        uri,
        headers: headers,
        body: body == null ? null : jsonEncode(body),
      );
    } else {
      throw ArgumentError.value(method, 'method', 'Unsupported HTTP method.');
    }

    final Map<String, Object?> decoded = _decodeJsonObject(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiException(response.statusCode, decoded);
    }
    return decoded;
  }

  static void _validateProjectPayload(
    Map<String, Object?> payload, {
    required bool includeDocument,
  }) {
    final Set<String> fields = <String>{
      'content_id',
      'group_id',
      'content_format',
      'status',
      'draft_revision',
      'assets',
      'created_at',
      'updated_at',
      if (includeDocument) 'document',
    };
    _requireExactFields(payload, fields, 'Authoring project response');
    _validateId(_requiredString(payload, 'content_id'), 'content_id');
    _validateId(_requiredString(payload, 'group_id'), 'group_id');
    _requiredString(payload, 'content_format');
    _requiredString(payload, 'status');
    _requiredPositiveInt(payload, 'draft_revision');
    _requiredString(payload, 'created_at');
    _requiredString(payload, 'updated_at');
    if (payload['assets'] is! List<Object?>) {
      throw const FormatException('Authoring project assets must be a list.');
    }
    if (includeDocument && payload['document'] is! Map<String, Object?>) {
      throw const FormatException('Authoring project document must be an object.');
    }
  }

  static Map<String, Object?> _decodeJsonObject(http.Response response) {
    final String? contentType = response.headers['content-type'];
    if (contentType == null ||
        !contentType.toLowerCase().startsWith('application/json')) {
      throw FormatException(
        'Authoring API returned a non-JSON response (HTTP ${response.statusCode}).',
      );
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Authoring API returned an unexpected JSON payload.');
    }
    return decoded;
  }

  static ApiException _apiException(
    int statusCode,
    Map<String, Object?> payload,
  ) {
    _requireExactFields(
      payload,
      const <String>{'error', 'message'},
      'Authoring API error response',
    );
    return ApiException(
      statusCode: statusCode,
      code: _requiredString(payload, 'error'),
      message: _requiredString(payload, 'message'),
    );
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
        'must be an HTTPS origin without credentials, path, query, or fragment',
      );
    }
    return uri;
  }
}

class HostedAuthoringBridgeProtocolException implements Exception {
  const HostedAuthoringBridgeProtocolException({
    required this.code,
    required this.message,
    this.requestId,
  });

  final String code;
  final String message;
  final String? requestId;
}

class HostedAuthoringBridgeRequest {
  const HostedAuthoringBridgeRequest({
    required this.id,
    required this.method,
    this.expectedRevision,
    this.document,
  });

  final String id;
  final String method;
  final int? expectedRevision;
  final Map<String, Object?>? document;
}

class HostedAuthoringBridgeProtocol {
  const HostedAuthoringBridgeProtocol._();

  static HostedAuthoringBridgeRequest decodeRequest(String message) {
    final Object? decoded;
    try {
      decoded = jsonDecode(message);
    } on FormatException catch (error) {
      throw HostedAuthoringBridgeProtocolException(
        code: 'invalid_authoring_bridge_request',
        message: 'Authoring bridge request must be valid JSON: ${error.message}',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const HostedAuthoringBridgeProtocolException(
        code: 'invalid_authoring_bridge_request',
        message: 'Authoring bridge request must be a JSON object.',
      );
    }
    final String? id = decoded['id'] is String ? decoded['id']! as String : null;
    if (decoded['version'] != hostedAuthoringBridgeVersion) {
      throw HostedAuthoringBridgeProtocolException(
        code: 'unsupported_authoring_bridge_version',
        message: 'Authoring bridge version must be $hostedAuthoringBridgeVersion.',
        requestId: id,
      );
    }
    if (id == null || !_authoringRequestIdPattern.hasMatch(id)) {
      throw const HostedAuthoringBridgeProtocolException(
        code: 'invalid_authoring_bridge_request',
        message: 'Authoring bridge request id is invalid.',
      );
    }
    final Object? rawMethod = decoded['method'];
    if (rawMethod != 'authoring.load' && rawMethod != 'authoring.save') {
      throw HostedAuthoringBridgeProtocolException(
        code: 'unsupported_authoring_bridge_method',
        message: 'Authoring bridge method is not supported.',
        requestId: id,
      );
    }

    if (rawMethod == 'authoring.load') {
      _requireBridgeFields(
        decoded,
        const <String>{'version', 'id', 'method'},
        id,
      );
      return HostedAuthoringBridgeRequest(id: id, method: rawMethod as String);
    }

    _requireBridgeFields(
      decoded,
      const <String>{'version', 'id', 'method', 'expectedRevision', 'data'},
      id,
    );
    final Object? rawRevision = decoded['expectedRevision'];
    if (rawRevision is! int || rawRevision is bool || rawRevision < 1) {
      throw HostedAuthoringBridgeProtocolException(
        code: 'invalid_expected_revision',
        message: 'expectedRevision must be a positive integer.',
        requestId: id,
      );
    }
    final Object? rawData = decoded['data'];
    if (rawData is! Map<String, Object?>) {
      throw HostedAuthoringBridgeProtocolException(
        code: 'invalid_master_data',
        message: 'Authoring save data must be a JSON object.',
        requestId: id,
      );
    }
    return HostedAuthoringBridgeRequest(
      id: id,
      method: rawMethod as String,
      expectedRevision: rawRevision,
      document: rawData,
    );
  }

  static Map<String, Object?> success(String id, Object? result) =>
      <String, Object?>{
        'version': hostedAuthoringBridgeVersion,
        'id': id,
        'ok': true,
        'result': result,
      };

  static Map<String, Object?> error({
    required String id,
    required int status,
    required String code,
    required String message,
  }) =>
      <String, Object?>{
        'version': hostedAuthoringBridgeVersion,
        'id': id,
        'ok': false,
        'error': <String, Object?>{
          'status': status,
          'code': code,
          'message': message,
        },
      };

  static const String bootstrapJavaScript = r'''
(() => {
  'use strict';
  const VERSION = 1;
  const channel = window.MinAppAuthoringBridge;
  if (!channel || typeof channel.postMessage !== 'function') {
    throw new Error('MinApp Authoring native bridge is unavailable.');
  }
  const current = window.minapp;
  if (!current || current.version !== VERSION) {
    throw new Error('MinApp Runtime bridge must be installed before Authoring.');
  }
  if (current.authoring && typeof window.__minappAuthoringBridgeReceive === 'function') {
    window.dispatchEvent(new Event('minappready'));
    return;
  }

  const pending = new Map();
  let nextId = 1;

  class MinAppAuthoringError extends Error {
    constructor(status, code, message) {
      super(message);
      this.name = 'MinAppAuthoringError';
      this.status = status;
      this.code = code;
    }
  }

  const send = (request) => new Promise((resolve, reject) => {
    const id = String(nextId++);
    request.version = VERSION;
    request.id = id;
    pending.set(id, { resolve, reject });
    try {
      channel.postMessage(JSON.stringify(request));
    } catch (error) {
      pending.delete(id);
      reject(new MinAppAuthoringError(0, 'bridge_unavailable', String(error)));
    }
  });

  Object.defineProperty(window, '__minappAuthoringBridgeReceive', {
    configurable: true,
    value: (response) => {
      if (!response || response.version !== VERSION || typeof response.id !== 'string') {
        throw new Error('Invalid MinApp Authoring bridge response.');
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
        waiter.reject(new MinAppAuthoringError(
          0,
          'invalid_bridge_response',
          'Invalid MinApp Authoring bridge error response.',
        ));
        return;
      }
      waiter.reject(new MinAppAuthoringError(error.status, error.code, error.message));
    },
  });

  const authoring = Object.freeze({
    load: () => send({ method: 'authoring.load' }),
    save: (data, options) => {
      if (!data || typeof data !== 'object' || Array.isArray(data)) {
        return Promise.reject(new MinAppAuthoringError(
          0,
          'invalid_master_data',
          'Authoring save data must be an object.',
        ));
      }
      const expectedRevision = options && options.expectedRevision;
      if (!Number.isInteger(expectedRevision) || expectedRevision < 1) {
        return Promise.reject(new MinAppAuthoringError(
          0,
          'invalid_expected_revision',
          'expectedRevision must be a positive integer.',
        ));
      }
      return send({
        method: 'authoring.save',
        expectedRevision,
        data,
      });
    },
  });

  Object.defineProperty(window, 'minapp', {
    configurable: true,
    value: Object.freeze(Object.assign({}, current, { authoring })),
  });
  window.dispatchEvent(new Event('minappready'));
})();
''';

  static void _requireBridgeFields(
    Map<String, Object?> payload,
    Set<String> expected,
    String id,
  ) {
    if (payload.keys.toSet().difference(expected).isNotEmpty ||
        expected.difference(payload.keys.toSet()).isNotEmpty) {
      throw HostedAuthoringBridgeProtocolException(
        code: 'invalid_authoring_bridge_request',
        message: 'Authoring bridge request fields do not match the method contract.',
        requestId: id,
      );
    }
  }
}

class HostedAuthoringBridgeSession {
  HostedAuthoringBridgeSession({
    required HostedAuthoringTransport transport,
    required String authoringToken,
  })  : _transport = transport,
        _authoringToken = _validatedAuthoringToken(authoringToken);

  final HostedAuthoringTransport _transport;
  final String _authoringToken;
  final Set<String> _inFlightRequestIds = <String>{};

  Future<Map<String, Object?>> handleMessage(String message) async {
    final HostedAuthoringBridgeRequest request;
    try {
      request = HostedAuthoringBridgeProtocol.decodeRequest(message);
    } on HostedAuthoringBridgeProtocolException catch (error) {
      return HostedAuthoringBridgeProtocol.error(
        id: error.requestId ?? '',
        status: 400,
        code: error.code,
        message: error.message,
      );
    }

    if (!_inFlightRequestIds.add(request.id)) {
      return HostedAuthoringBridgeProtocol.error(
        id: request.id,
        status: 409,
        code: 'duplicate_request_id',
        message: 'An Authoring bridge request with this id is already in flight.',
      );
    }

    try {
      final Object? result;
      if (request.method == 'authoring.load') {
        result = await _transport.loadProject(_authoringToken);
      } else if (request.method == 'authoring.save') {
        final int? expectedRevision = request.expectedRevision;
        final Map<String, Object?>? document = request.document;
        if (expectedRevision == null || document == null) {
          throw StateError('Validated Authoring save request lost required fields.');
        }
        result = await _transport.saveDocument(
          _authoringToken,
          expectedRevision: expectedRevision,
          document: document,
        );
      } else {
        throw StateError('Validated Authoring bridge request has an unsupported method.');
      }
      return HostedAuthoringBridgeProtocol.success(request.id, result);
    } on ApiException catch (error) {
      return HostedAuthoringBridgeProtocol.error(
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

class HostedAuthoringBridgeDocumentInjector {
  int _finishedDocumentCount = 0;

  int get finishedDocumentCount => _finishedDocumentCount;

  String scriptForFinishedDocument() {
    _finishedDocumentCount += 1;
    return HostedAuthoringBridgeProtocol.bootstrapJavaScript;
  }
}

void _validateId(String value, String name) {
  if (!_authoringIdPattern.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      name,
      'must be a 32-character lowercase hexadecimal id',
    );
  }
}

void _validateAccessToken(String value) {
  if (value.isEmpty) {
    throw ArgumentError.value(value, 'accessToken', 'must not be empty');
  }
}

void _validateAuthoringToken(String token) {
  if (!_authoringTokenPattern.hasMatch(token)) {
    throw ArgumentError.value(token, 'authoringToken', 'has an invalid format');
  }
}

String _validatedAuthoringToken(String token) {
  _validateAuthoringToken(token);
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
  if (value is! int || value is bool || value < 1) {
    throw FormatException('JSON field $key must be a positive integer.');
  }
  return value;
}

List<String> _requiredStringList(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! List<Object?> ||
      value.isEmpty ||
      value.any((Object? item) => item is! String || item.isEmpty)) {
    throw FormatException('JSON field $key must be a non-empty string list.');
  }
  final List<String> result = value.cast<String>();
  if (result.toSet().length != result.length) {
    throw FormatException('JSON field $key must not contain duplicates.');
  }
  return result;
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
    throw FormatException('$context has unexpected fields.');
  }
}
