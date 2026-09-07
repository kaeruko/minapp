import 'dart:convert';

import 'api.dart';

const int hostedAuthoringPreviewBridgeVersion = 1;

final RegExp _authoringPreviewRequestIdPattern = RegExp(
  r'^[A-Za-z0-9_-]{1,64}$',
);

typedef HostedAuthoringPreviewHost = Future<Object?> Function(
  int expectedRevision,
);

class HostedAuthoringPreviewHostException implements Exception {
  const HostedAuthoringPreviewHostException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;
}

class HostedAuthoringPreviewBridgeProtocolException implements Exception {
  const HostedAuthoringPreviewBridgeProtocolException({
    required this.code,
    required this.message,
    this.requestId,
  });

  final String code;
  final String message;
  final String? requestId;
}

class HostedAuthoringPreviewBridgeRequest {
  const HostedAuthoringPreviewBridgeRequest({
    required this.id,
    required this.expectedRevision,
  });

  final String id;
  final int expectedRevision;
}

class HostedAuthoringPreviewBridgeProtocol {
  const HostedAuthoringPreviewBridgeProtocol._();

  static HostedAuthoringPreviewBridgeRequest decodeRequest(String message) {
    final Object? decoded;
    try {
      decoded = jsonDecode(message);
    } on FormatException catch (error) {
      throw HostedAuthoringPreviewBridgeProtocolException(
        code: 'invalid_authoring_preview_request',
        message: 'Authoring preview request must be valid JSON: ${error.message}',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const HostedAuthoringPreviewBridgeProtocolException(
        code: 'invalid_authoring_preview_request',
        message: 'Authoring preview request must be a JSON object.',
      );
    }

    final String? id = decoded['id'] is String ? decoded['id']! as String : null;
    if (decoded['version'] != hostedAuthoringPreviewBridgeVersion) {
      throw HostedAuthoringPreviewBridgeProtocolException(
        code: 'unsupported_authoring_preview_bridge_version',
        message:
            'Authoring preview bridge version must be $hostedAuthoringPreviewBridgeVersion.',
        requestId: id,
      );
    }
    if (id == null || !_authoringPreviewRequestIdPattern.hasMatch(id)) {
      throw const HostedAuthoringPreviewBridgeProtocolException(
        code: 'invalid_authoring_preview_request',
        message: 'Authoring preview request id is invalid.',
      );
    }
    _requireExactFields(
      decoded,
      const <String>{'version', 'id', 'method', 'expectedRevision'},
      id,
    );
    if (decoded['method'] != 'authoring.preview') {
      throw HostedAuthoringPreviewBridgeProtocolException(
        code: 'unsupported_authoring_preview_method',
        message: 'Authoring preview bridge method is not supported.',
        requestId: id,
      );
    }
    final Object? rawRevision = decoded['expectedRevision'];
    if (rawRevision is! int || rawRevision is bool || rawRevision < 1) {
      throw HostedAuthoringPreviewBridgeProtocolException(
        code: 'invalid_expected_revision',
        message: 'expectedRevision must be a positive integer.',
        requestId: id,
      );
    }
    return HostedAuthoringPreviewBridgeRequest(
      id: id,
      expectedRevision: rawRevision,
    );
  }

  static Map<String, Object?> success(String id, Object? result) =>
      <String, Object?>{
        'version': hostedAuthoringPreviewBridgeVersion,
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
        'version': hostedAuthoringPreviewBridgeVersion,
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
  const channel = window.MinAppAuthoringPreviewBridge;
  if (!channel || typeof channel.postMessage !== 'function') {
    throw new Error('MinApp Authoring Preview native bridge is unavailable.');
  }
  const current = window.minapp;
  if (!current || current.version !== VERSION || !current.authoring) {
    throw new Error('MinApp Authoring bridge must be installed before Preview.');
  }
  if (typeof current.authoring.preview === 'function' &&
      typeof window.__minappAuthoringPreviewBridgeReceive === 'function') {
    window.dispatchEvent(new Event('minappready'));
    return;
  }

  const pending = new Map();
  let nextId = 1;

  class MinAppAuthoringPreviewError extends Error {
    constructor(status, code, message) {
      super(message);
      this.name = 'MinAppAuthoringPreviewError';
      this.status = status;
      this.code = code;
    }
  }

  const send = (request) => new Promise((resolve, reject) => {
    const id = `preview-${nextId++}`;
    request.version = VERSION;
    request.id = id;
    pending.set(id, { resolve, reject });
    try {
      channel.postMessage(JSON.stringify(request));
    } catch (error) {
      pending.delete(id);
      reject(new MinAppAuthoringPreviewError(
        0,
        'preview_bridge_unavailable',
        String(error),
      ));
    }
  });

  Object.defineProperty(window, '__minappAuthoringPreviewBridgeReceive', {
    configurable: true,
    value: (response) => {
      if (!response || response.version !== VERSION || typeof response.id !== 'string') {
        throw new Error('Invalid MinApp Authoring Preview bridge response.');
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
        waiter.reject(new MinAppAuthoringPreviewError(
          0,
          'invalid_preview_bridge_response',
          'Invalid MinApp Authoring Preview bridge error response.',
        ));
        return;
      }
      waiter.reject(new MinAppAuthoringPreviewError(
        error.status,
        error.code,
        error.message,
      ));
    },
  });

  const preview = (options) => {
    const expectedRevision = options && options.expectedRevision;
    if (!Number.isInteger(expectedRevision) || expectedRevision < 1) {
      return Promise.reject(new MinAppAuthoringPreviewError(
        0,
        'invalid_expected_revision',
        'expectedRevision must be a positive integer.',
      ));
    }
    return send({ method: 'authoring.preview', expectedRevision });
  };

  const authoring = Object.freeze(Object.assign({}, current.authoring, { preview }));
  Object.defineProperty(window, 'minapp', {
    configurable: true,
    value: Object.freeze(Object.assign({}, current, { authoring })),
  });
  window.dispatchEvent(new Event('minappready'));
})();
''';

  static void _requireExactFields(
    Map<String, Object?> payload,
    Set<String> expected,
    String id,
  ) {
    final Set<String> actual = payload.keys.toSet();
    if (actual.length != expected.length ||
        actual.difference(expected).isNotEmpty ||
        expected.difference(actual).isNotEmpty) {
      throw HostedAuthoringPreviewBridgeProtocolException(
        code: 'invalid_authoring_preview_request',
        message: 'Authoring preview request fields do not match the method contract.',
        requestId: id,
      );
    }
  }
}

class HostedAuthoringPreviewBridgeSession {
  HostedAuthoringPreviewBridgeSession({required HostedAuthoringPreviewHost preview})
      : _preview = preview;

  final HostedAuthoringPreviewHost _preview;
  final Set<String> _inFlightRequestIds = <String>{};

  Future<Map<String, Object?>> handleMessage(String message) async {
    final HostedAuthoringPreviewBridgeRequest request;
    try {
      request = HostedAuthoringPreviewBridgeProtocol.decodeRequest(message);
    } on HostedAuthoringPreviewBridgeProtocolException catch (error) {
      return HostedAuthoringPreviewBridgeProtocol.error(
        id: error.requestId ?? '',
        status: 400,
        code: error.code,
        message: error.message,
      );
    }

    if (!_inFlightRequestIds.add(request.id)) {
      return HostedAuthoringPreviewBridgeProtocol.error(
        id: request.id,
        status: 409,
        code: 'duplicate_request_id',
        message: 'An Authoring Preview request with this id is already in flight.',
      );
    }

    try {
      final Object? result = await _preview(request.expectedRevision);
      return HostedAuthoringPreviewBridgeProtocol.success(request.id, result);
    } on ApiException catch (error) {
      return HostedAuthoringPreviewBridgeProtocol.error(
        id: request.id,
        status: error.statusCode,
        code: error.code,
        message: error.message,
      );
    } on HostedAuthoringPreviewHostException catch (error) {
      return HostedAuthoringPreviewBridgeProtocol.error(
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

class HostedAuthoringPreviewBridgeDocumentInjector {
  int _finishedDocumentCount = 0;

  int get finishedDocumentCount => _finishedDocumentCount;

  String scriptForFinishedDocument() {
    _finishedDocumentCount += 1;
    return HostedAuthoringPreviewBridgeProtocol.bootstrapJavaScript;
  }
}
