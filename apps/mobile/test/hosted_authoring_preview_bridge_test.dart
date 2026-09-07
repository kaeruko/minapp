import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/api.dart';
import 'package:minapp_mobile/hosted_authoring_preview_bridge.dart';

void main() {
  test('preview bridge sends only the expected draft revision to the trusted Host', () async {
    int? seenRevision;
    final HostedAuthoringPreviewBridgeSession session =
        HostedAuthoringPreviewBridgeSession(
      preview: (int expectedRevision) async {
        seenRevision = expectedRevision;
        return <String, Object?>{
          'content_format': 'example/quiz@1',
          'draft_revision': expectedRevision,
          'player_app_id': 'a' * 32,
        };
      },
    );

    final Map<String, Object?> response = await session.handleMessage(
      jsonEncode(<String, Object?>{
        'version': 1,
        'id': 'preview-1',
        'method': 'authoring.preview',
        'expectedRevision': 7,
      }),
    );

    expect(seenRevision, 7);
    expect(response['ok'], isTrue);
    final Map<String, Object?> result =
        response['result']! as Map<String, Object?>;
    expect(result['draft_revision'], 7);
  });

  test('preview bridge rejects child-selected content and Player scope', () async {
    var called = false;
    final HostedAuthoringPreviewBridgeSession session =
        HostedAuthoringPreviewBridgeSession(
      preview: (int expectedRevision) async {
        called = true;
        return null;
      },
    );

    final Map<String, Object?> response = await session.handleMessage(
      jsonEncode(<String, Object?>{
        'version': 1,
        'id': 'preview-scope',
        'method': 'authoring.preview',
        'expectedRevision': 7,
        'contentId': 'b' * 32,
        'playerAppId': 'c' * 32,
      }),
    );

    expect(response['ok'], isFalse);
    final Map<String, Object?> error =
        response['error']! as Map<String, Object?>;
    expect(error['code'], 'invalid_authoring_preview_request');
    expect(called, isFalse);
  });

  test('preview bridge preserves API error status code and message', () async {
    final HostedAuthoringPreviewBridgeSession session =
        HostedAuthoringPreviewBridgeSession(
      preview: (int expectedRevision) async {
        throw const ApiException(
          statusCode: 409,
          code: 'revision_conflict',
          message: 'Draft revision changed.',
        );
      },
    );

    final Map<String, Object?> response = await session.handleMessage(
      jsonEncode(<String, Object?>{
        'version': 1,
        'id': 'preview-error',
        'method': 'authoring.preview',
        'expectedRevision': 4,
      }),
    );

    expect(response['ok'], isFalse);
    final Map<String, Object?> error =
        response['error']! as Map<String, Object?>;
    expect(error['status'], 409);
    expect(error['code'], 'revision_conflict');
    expect(error['message'], 'Draft revision changed.');
  });

  test('preview bridge rejects duplicate in-flight request ids', () async {
    final Completer<Object?> completer = Completer<Object?>();
    final HostedAuthoringPreviewBridgeSession session =
        HostedAuthoringPreviewBridgeSession(
      preview: (int expectedRevision) => completer.future,
    );
    final String message = jsonEncode(<String, Object?>{
      'version': 1,
      'id': 'preview-duplicate',
      'method': 'authoring.preview',
      'expectedRevision': 2,
    });

    final Future<Map<String, Object?>> first = session.handleMessage(message);
    final Map<String, Object?> second = await session.handleMessage(message);
    expect(second['ok'], isFalse);
    final Map<String, Object?> error =
        second['error']! as Map<String, Object?>;
    expect(error['code'], 'duplicate_request_id');

    completer.complete(null);
    expect((await first)['ok'], isTrue);
  });

  test('preview bootstrap exposes host preview without credentials or scope selectors', () {
    final String script =
        HostedAuthoringPreviewBridgeProtocol.bootstrapJavaScript;
    expect(script, contains('authoring.preview'));
    expect(script, contains('expectedRevision'));
    expect(script, isNot(contains('contentId')));
    expect(script, isNot(contains('playerAppId')));
    expect(script.toLowerCase(), isNot(contains('cognito')));
    expect(script.toLowerCase(), isNot(contains('authorization')));
  });
}
