import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api.dart';

const int hostedAuthoringBridgeVersion = 1;

final RegExp _authoringIdPattern = RegExp(r'^[0-9a-f]{32}$');
final RegExp _authoringTokenPattern = RegExp(r'^[A-Za-z0-9_-]{32,64}$');
final RegExp _authoringRequestIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
const Map<String, String> _authoringAssetContentTypes = <String, String>{
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.mp3': 'audio/mpeg',
  '.m4a': 'audio/mp4',
  '.ogg': 'audio/ogg',
  '.wav': 'audio/wav',
};

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

class HostedAuthoringAssetData {
  HostedAuthoringAssetData(
      {required Uint8List bytes, required this.contentType})
      : bytes = Uint8List.fromList(bytes);

  final Uint8List bytes;
  final String contentType;
}

abstract interface class HostedAuthoringTransport {
  Future<Map<String, Object?>> loadProject(String authoringToken);

  Future<HostedAuthoringAssetData> getAsset(
    String authoringToken, {
    required String path,
  });

  Future<Map<String, Object?>> saveAsset(
    String authoringToken, {
    required int expectedRevision,
    required String path,
    required Uint8List bytes,
  });

  Future<Map<String, Object?>> deleteAsset(
    String authoringToken, {
    required int expectedRevision,
    required String path,
  });

  Future<Map<String, Object?>> saveDocument(
    String authoringToken, {
    required int expectedRevision,
    required Map<String, Object?> document,
  });

  Future<Map<String, Object?>> publishProject(
    String authoringToken, {
    required int expectedRevision,
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
    final String returnedEditorAppId =
        _requiredString(payload, 'editor_app_id');
    if (returnedContentId != contentId || returnedEditorAppId != editorAppId) {
      throw const FormatException(
          'Authoring session response changed the requested scope.');
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
  Future<HostedAuthoringAssetData> getAsset(
    String authoringToken, {
    required String path,
  }) async {
    _validateAuthoringToken(authoringToken);
    final String normalizedPath = _validateAuthoringAssetPath(path);
    final String expectedContentType =
        _authoringAssetContentType(normalizedPath);
    final Uri uri = _baseUri
        .resolve(_authoringAssetApiPath(authoringToken, normalizedPath));
    final http.Response response = await _client.get(
      uri,
      headers: const <String, String>{'Accept': '*/*'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiException(response.statusCode, _decodeJsonObject(response));
    }
    final String? rawContentType = response.headers['content-type'];
    final String contentType = rawContentType == null
        ? ''
        : rawContentType.split(';').first.trim().toLowerCase();
    if (contentType != expectedContentType) {
      throw FormatException(
        'Authoring asset response Content-Type must be $expectedContentType.',
      );
    }
    return HostedAuthoringAssetData(
      bytes: response.bodyBytes,
      contentType: contentType,
    );
  }

  @override
  Future<Map<String, Object?>> saveAsset(
    String authoringToken, {
    required int expectedRevision,
    required String path,
    required Uint8List bytes,
  }) async {
    _validateAuthoringToken(authoringToken);
    _validateExpectedRevision(expectedRevision);
    final String normalizedPath = _validateAuthoringAssetPath(path);
    final String contentType = _authoringAssetContentType(normalizedPath);
    final Uri uri = _baseUri
        .resolve(_authoringAssetApiPath(authoringToken, normalizedPath));
    final http.Response response = await _client.post(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Content-Type': contentType,
        'x-minapp-expected-revision': '$expectedRevision',
      },
      body: bytes,
    );
    final Map<String, Object?> payload = _decodeJsonObject(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiException(response.statusCode, payload);
    }
    _validateProjectPayload(payload, includeDocument: false);
    if (payload['draft_revision'] != expectedRevision + 1) {
      throw const FormatException(
        'Authoring asset mutation did not advance exactly one draft revision.',
      );
    }
    return payload;
  }

  @override
  Future<Map<String, Object?>> deleteAsset(
    String authoringToken, {
    required int expectedRevision,
    required String path,
  }) async {
    _validateAuthoringToken(authoringToken);
    _validateExpectedRevision(expectedRevision);
    final String normalizedPath = _validateAuthoringAssetPath(path);
    final Uri uri = _baseUri
        .resolve(_authoringAssetApiPath(authoringToken, normalizedPath));
    final http.Response response = await _client.delete(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'x-minapp-expected-revision': '$expectedRevision',
      },
    );
    final Map<String, Object?> payload = _decodeJsonObject(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiException(response.statusCode, payload);
    }
    _validateProjectPayload(payload, includeDocument: false);
    if (payload['draft_revision'] != expectedRevision + 1) {
      throw const FormatException(
        'Authoring asset mutation did not advance exactly one draft revision.',
      );
    }
    return payload;
  }

  @override
  Future<Map<String, Object?>> saveDocument(
    String authoringToken, {
    required int expectedRevision,
    required Map<String, Object?> document,
  }) async {
    _validateAuthoringToken(authoringToken);
    _validateExpectedRevision(expectedRevision);
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

  @override
  Future<Map<String, Object?>> publishProject(
    String authoringToken, {
    required int expectedRevision,
  }) async {
    _validateAuthoringToken(authoringToken);
    _validateExpectedRevision(expectedRevision);
    final Map<String, Object?> payload = await _jsonRequest(
      method: 'POST',
      path: '/hosted/authoring/session/$authoringToken/publish',
      body: <String, Object?>{'expected_revision': expectedRevision},
    );
    _validatePublishPayload(payload);
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
      if (body != null)
        throw ArgumentError('GET request must not contain a body.');
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
      throw const FormatException(
          'Authoring project document must be an object.');
    }
  }

  static void _validatePublishPayload(Map<String, Object?> payload) {
    _requireExactFields(
      payload,
      const <String>{
        'content_id',
        'group_id',
        'content_format',
        'published_version',
        'source_revision',
        'published_app_id',
        'player_app_id',
        'player_source_version',
        'assets',
        'published_at',
      },
      'Authoring publish response',
    );
    _validateId(_requiredString(payload, 'content_id'), 'content_id');
    _validateId(_requiredString(payload, 'group_id'), 'group_id');
    _validateId(
        _requiredString(payload, 'published_app_id'), 'published_app_id');
    _validateId(_requiredString(payload, 'player_app_id'), 'player_app_id');
    _requiredString(payload, 'content_format');
    _requiredPositiveInt(payload, 'published_version');
    _requiredPositiveInt(payload, 'source_revision');
    _requiredPositiveInt(payload, 'player_source_version');
    _requiredString(payload, 'published_at');
    if (payload['assets'] is! List<Object?>) {
      throw const FormatException('Authoring publish assets must be a list.');
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
      throw const FormatException(
          'Authoring API returned an unexpected JSON payload.');
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
    this.assetPath,
    this.assetBytes,
  });

  final String id;
  final String method;
  final int? expectedRevision;
  final Map<String, Object?>? document;
  final String? assetPath;
  final Uint8List? assetBytes;
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
        message:
            'Authoring bridge request must be valid JSON: ${error.message}',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const HostedAuthoringBridgeProtocolException(
        code: 'invalid_authoring_bridge_request',
        message: 'Authoring bridge request must be a JSON object.',
      );
    }
    final String? id =
        decoded['id'] is String ? decoded['id']! as String : null;
    if (decoded['version'] != hostedAuthoringBridgeVersion) {
      throw HostedAuthoringBridgeProtocolException(
        code: 'unsupported_authoring_bridge_version',
        message:
            'Authoring bridge version must be $hostedAuthoringBridgeVersion.',
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
    if (rawMethod != 'authoring.load' &&
        rawMethod != 'authoring.save' &&
        rawMethod != 'authoring.getAsset' &&
        rawMethod != 'authoring.saveAsset' &&
        rawMethod != 'authoring.deleteAsset' &&
        rawMethod != 'authoring.publish') {
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

    if (rawMethod == 'authoring.getAsset') {
      _requireBridgeFields(
        decoded,
        const <String>{'version', 'id', 'method', 'path'},
        id,
      );
      return HostedAuthoringBridgeRequest(
        id: id,
        method: rawMethod as String,
        assetPath: _bridgeAssetPath(decoded['path'], id),
      );
    }

    if (rawMethod == 'authoring.saveAsset' ||
        rawMethod == 'authoring.deleteAsset') {
      final Set<String> expectedFields = rawMethod == 'authoring.saveAsset'
          ? const <String>{
              'version',
              'id',
              'method',
              'path',
              'expectedRevision',
              'dataBase64'
            }
          : const <String>{
              'version',
              'id',
              'method',
              'path',
              'expectedRevision'
            };
      _requireBridgeFields(decoded, expectedFields, id);
      final Object? rawRevision = decoded['expectedRevision'];
      if (rawRevision is! int || rawRevision is bool || rawRevision < 1) {
        throw HostedAuthoringBridgeProtocolException(
          code: 'invalid_expected_revision',
          message: 'expectedRevision must be a positive integer.',
          requestId: id,
        );
      }
      Uint8List? assetBytes;
      if (rawMethod == 'authoring.saveAsset') {
        final Object? encoded = decoded['dataBase64'];
        if (encoded is! String || encoded.isEmpty) {
          throw HostedAuthoringBridgeProtocolException(
            code: 'invalid_authoring_asset_data',
            message: 'Authoring asset data must be non-empty base64.',
            requestId: id,
          );
        }
        try {
          assetBytes = base64Decode(encoded);
        } on FormatException {
          throw HostedAuthoringBridgeProtocolException(
            code: 'invalid_authoring_asset_data',
            message: 'Authoring asset data must be valid base64.',
            requestId: id,
          );
        }
        if (assetBytes.isEmpty) {
          throw HostedAuthoringBridgeProtocolException(
            code: 'invalid_authoring_asset_data',
            message: 'Authoring asset data must not be empty.',
            requestId: id,
          );
        }
      }
      return HostedAuthoringBridgeRequest(
        id: id,
        method: rawMethod as String,
        expectedRevision: rawRevision,
        assetPath: _bridgeAssetPath(decoded['path'], id),
        assetBytes: assetBytes,
      );
    }

    final Set<String> expectedFields = rawMethod == 'authoring.save'
        ? const <String>{'version', 'id', 'method', 'expectedRevision', 'data'}
        : const <String>{'version', 'id', 'method', 'expectedRevision'};
    _requireBridgeFields(decoded, expectedFields, id);
    final Object? rawRevision = decoded['expectedRevision'];
    if (rawRevision is! int || rawRevision is bool || rawRevision < 1) {
      throw HostedAuthoringBridgeProtocolException(
        code: 'invalid_expected_revision',
        message: 'expectedRevision must be a positive integer.',
        requestId: id,
      );
    }
    if (rawMethod == 'authoring.publish') {
      return HostedAuthoringBridgeRequest(
        id: id,
        method: rawMethod as String,
        expectedRevision: rawRevision,
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

  static String _bridgeAssetPath(Object? value, String id) {
    if (value is! String) {
      throw HostedAuthoringBridgeProtocolException(
        code: 'invalid_authoring_asset_path',
        message: 'Authoring asset path is invalid.',
        requestId: id,
      );
    }
    try {
      return _validateAuthoringAssetPath(value);
    } on ArgumentError {
      throw HostedAuthoringBridgeProtocolException(
        code: 'invalid_authoring_asset_path',
        message: 'Authoring asset path is invalid or unsupported.',
        requestId: id,
      );
    }
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

  const validateExpectedRevision = (options) => {
    const expectedRevision = options && options.expectedRevision;
    if (!Number.isInteger(expectedRevision) || expectedRevision < 1) {
      throw new MinAppAuthoringError(
        0,
        'invalid_expected_revision',
        'expectedRevision must be a positive integer.',
      );
    }
    return expectedRevision;
  };

  const ASSET_EXTENSIONS = new Set(['png', 'jpg', 'jpeg', 'gif', 'webp', 'mp3', 'm4a', 'ogg', 'wav']);
  const validateAssetPath = (path) => {
    if (typeof path !== 'string' || path.length === 0 || path.length > 256 ||
        path.startsWith('/') || path.includes('\\') || path.includes('\0')) {
      throw new MinAppAuthoringError(0, 'invalid_authoring_asset_path', 'Authoring asset path is invalid.');
    }
    const parts = path.split('/');
    if (parts.some((part) => part === '' || part === '.' || part === '..')) {
      throw new MinAppAuthoringError(0, 'invalid_authoring_asset_path', 'Authoring asset path is invalid.');
    }
    const name = parts[parts.length - 1];
    const dot = name.lastIndexOf('.');
    const extension = dot < 0 ? '' : name.slice(dot + 1).toLowerCase();
    if (!ASSET_EXTENSIONS.has(extension)) {
      throw new MinAppAuthoringError(0, 'unsupported_authoring_asset_type', 'Authoring asset type is not supported.');
    }
    return path;
  };
  const encodeAssetBytes = (bytes) => {
    if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
      throw new MinAppAuthoringError(0, 'invalid_authoring_asset_data', 'Authoring asset bytes must be a non-empty Uint8Array.');
    }
    let binary = '';
    for (let offset = 0; offset < bytes.length; offset += 0x8000) {
      binary += String.fromCharCode(...bytes.subarray(offset, Math.min(offset + 0x8000, bytes.length)));
    }
    return btoa(binary);
  };
  const decodeAssetResult = (result) => {
    if (!result || typeof result !== 'object' || Array.isArray(result) ||
        Object.keys(result).sort().join(',') !== 'contentType,dataBase64' ||
        typeof result.dataBase64 !== 'string' || result.dataBase64.length === 0 ||
        typeof result.contentType !== 'string' || result.contentType.length === 0) {
      throw new MinAppAuthoringError(0, 'invalid_bridge_response', 'Authoring asset response is invalid.');
    }
    const binary = atob(result.dataBase64);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
    return Object.freeze({ bytes, contentType: result.contentType });
  };

  const authoring = Object.freeze({
    load: () => send({ method: 'authoring.load' }),
    getAsset: (path) => {
      try {
        return send({ method: 'authoring.getAsset', path: validateAssetPath(path) }).then(decodeAssetResult);
      } catch (error) {
        return Promise.reject(error);
      }
    },
    saveAsset: (path, bytes, options) => {
      let expectedRevision;
      let normalizedPath;
      let dataBase64;
      try {
        normalizedPath = validateAssetPath(path);
        dataBase64 = encodeAssetBytes(bytes);
        expectedRevision = validateExpectedRevision(options);
      } catch (error) {
        return Promise.reject(error);
      }
      return send({ method: 'authoring.saveAsset', path: normalizedPath, expectedRevision, dataBase64 });
    },
    deleteAsset: (path, options) => {
      let expectedRevision;
      let normalizedPath;
      try {
        normalizedPath = validateAssetPath(path);
        expectedRevision = validateExpectedRevision(options);
      } catch (error) {
        return Promise.reject(error);
      }
      return send({ method: 'authoring.deleteAsset', path: normalizedPath, expectedRevision });
    },
    save: (data, options) => {
      if (!data || typeof data !== 'object' || Array.isArray(data)) {
        return Promise.reject(new MinAppAuthoringError(
          0,
          'invalid_master_data',
          'Authoring save data must be an object.',
        ));
      }
      let expectedRevision;
      try {
        expectedRevision = validateExpectedRevision(options);
      } catch (error) {
        return Promise.reject(error);
      }
      return send({
        method: 'authoring.save',
        expectedRevision,
        data,
      });
    },
    publish: (options) => {
      let expectedRevision;
      try {
        expectedRevision = validateExpectedRevision(options);
      } catch (error) {
        return Promise.reject(error);
      }
      return send({ method: 'authoring.publish', expectedRevision });
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
        message:
            'Authoring bridge request fields do not match the method contract.',
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
        message:
            'An Authoring bridge request with this id is already in flight.',
      );
    }

    try {
      final Object? result;
      if (request.method == 'authoring.load') {
        result = await _transport.loadProject(_authoringToken);
      } else if (request.method == 'authoring.getAsset') {
        final String? assetPath = request.assetPath;
        if (assetPath == null) {
          throw StateError('Validated Authoring getAsset request lost path.');
        }
        final HostedAuthoringAssetData asset = await _transport.getAsset(
          _authoringToken,
          path: assetPath,
        );
        result = <String, Object?>{
          'dataBase64': base64Encode(asset.bytes),
          'contentType': asset.contentType,
        };
      } else if (request.method == 'authoring.saveAsset') {
        final int? expectedRevision = request.expectedRevision;
        final String? assetPath = request.assetPath;
        final Uint8List? assetBytes = request.assetBytes;
        if (expectedRevision == null ||
            assetPath == null ||
            assetBytes == null) {
          throw StateError(
              'Validated Authoring saveAsset request lost required fields.');
        }
        result = await _transport.saveAsset(
          _authoringToken,
          expectedRevision: expectedRevision,
          path: assetPath,
          bytes: assetBytes,
        );
      } else if (request.method == 'authoring.deleteAsset') {
        final int? expectedRevision = request.expectedRevision;
        final String? assetPath = request.assetPath;
        if (expectedRevision == null || assetPath == null) {
          throw StateError(
              'Validated Authoring deleteAsset request lost required fields.');
        }
        result = await _transport.deleteAsset(
          _authoringToken,
          expectedRevision: expectedRevision,
          path: assetPath,
        );
      } else if (request.method == 'authoring.save') {
        final int? expectedRevision = request.expectedRevision;
        final Map<String, Object?>? document = request.document;
        if (expectedRevision == null || document == null) {
          throw StateError(
              'Validated Authoring save request lost required fields.');
        }
        result = await _transport.saveDocument(
          _authoringToken,
          expectedRevision: expectedRevision,
          document: document,
        );
      } else if (request.method == 'authoring.publish') {
        final int? expectedRevision = request.expectedRevision;
        if (expectedRevision == null) {
          throw StateError(
              'Validated Authoring publish request lost expectedRevision.');
        }
        result = await _transport.publishProject(
          _authoringToken,
          expectedRevision: expectedRevision,
        );
      } else {
        throw StateError(
            'Validated Authoring bridge request has an unsupported method.');
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

String _validateAuthoringAssetPath(String path) {
  if (path.isEmpty ||
      path.length > 256 ||
      path.contains('\\') ||
      path.contains('\u0000') ||
      path.startsWith('/')) {
    throw ArgumentError.value(
        path, 'path', 'is not a valid Authoring asset path');
  }
  final List<String> parts = path.split('/');
  if (parts.any((String part) => part.isEmpty || part == '.' || part == '..')) {
    throw ArgumentError.value(
        path, 'path', 'is not a valid Authoring asset path');
  }
  _authoringAssetContentType(path);
  return parts.join('/');
}

String _authoringAssetContentType(String path) {
  final String name = path.split('/').last;
  final int dot = name.lastIndexOf('.');
  final String suffix = dot < 0 ? '' : name.substring(dot).toLowerCase();
  final String? contentType = _authoringAssetContentTypes[suffix];
  if (contentType == null) {
    throw ArgumentError.value(
        path, 'path', 'has an unsupported Authoring asset type');
  }
  return contentType;
}

String _authoringAssetApiPath(String token, String path) {
  final String encodedPath = path.split('/').map(Uri.encodeComponent).join('/');
  return '/hosted/authoring/session/$token/assets/$encodedPath';
}

void _validateExpectedRevision(int value) {
  if (value < 1) {
    throw ArgumentError.value(
      value,
      'expectedRevision',
      'must be a positive integer',
    );
  }
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
