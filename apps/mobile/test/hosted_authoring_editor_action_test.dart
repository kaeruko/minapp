import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/hosted_authoring_contract_api.dart';
import 'package:minapp_mobile/hosted_authoring_editor_action.dart';
import 'package:minapp_mobile/hosted_runtime_bridge.dart';

const String _groupId = '22222222222222222222222222222222';
const String _appId = '44444444444444444444444444444444';

class _NoopRuntimeTransport implements HostedRuntimeTransport {
  @override
  Future<void> deleteState(String runtimeToken, String key) async {
    throw StateError('Runtime transport must not be used while rendering.');
  }

  @override
  Future<Object?> getState(String runtimeToken, String key) async {
    throw StateError('Runtime transport must not be used while rendering.');
  }

  @override
  Future<Object?> setState(
    String runtimeToken,
    String key,
    Object? value,
  ) async {
    throw StateError('Runtime transport must not be used while rendering.');
  }
}

HostedAuthoringContractApi _contractApi({
  required bool editor,
  List<String>? editorFormats,
}) {
  final List<String> edits = editor
      ? (editorFormats ?? const <String>['example/quiz@1'])
      : const <String>[];
  return HostedAuthoringContractApi(
    baseUri: Uri.parse('https://hosted.example.test'),
    client: MockClient((http.Request request) async {
      expect(
        request.url.path,
        '/hosted/authoring/groups/$_groupId/apps',
      );
      expect(request.headers['Authorization'], 'Bearer owner-token');
      return http.Response(
        jsonEncode(<String, Object?>{
          'apps': <Object?>[
            <String, Object?>{
              'app_id': _appId,
              'group_id': _groupId,
              'title': editor ? 'Quiz Editor' : 'Quiz Player',
              'edits': edits,
              'accepts': editor ? <String>[] : <String>['example/quiz@1'],
            },
          ],
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    }),
  );
}

Widget _subject({
  required HostedAuthoringContractApi contractApi,
}) {
  return MaterialApp(
    home: Scaffold(
      body: HostedAuthoringEditorAction(
        baseUri: Uri.parse('https://hosted.example.test'),
        accessToken: 'owner-token',
        groupId: _groupId,
        editorAppId: _appId,
        runtimeTransport: _NoopRuntimeTransport(),
        authoringContractApi: contractApi,
        errorMessage: (Object error) => error.toString(),
        nonEditorChild: const Text(
          '通常アクション',
          key: Key('non-editor-actions'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('third-party Editor exposes generic Authoring action', (
    WidgetTester tester,
  ) async {
    final HostedAuthoringContractApi contractApi = _contractApi(editor: true);
    addTearDown(contractApi.close);

    await tester.pumpWidget(_subject(contractApi: contractApi));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('hosted-authoring-open-projects')),
      findsOneWidget,
    );
    expect(find.text('作品を編集'), findsOneWidget);
    expect(find.byKey(const Key('non-editor-actions')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multiple Editor formats require explicit shared selection', (
    WidgetTester tester,
  ) async {
    final HostedAuthoringContractApi contractApi = _contractApi(
      editor: true,
      editorFormats: const <String>['example/quiz@1', 'example/quiz@2'],
    );
    addTearDown(contractApi.close);

    await tester.pumpWidget(_subject(contractApi: contractApi));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('hosted-authoring-open-projects')));
    await tester.pumpAndSettle();

    expect(find.text('どの作品形式を編集する？'), findsOneWidget);
    expect(
      find.byKey(const Key('hosted-authoring-format-example/quiz@1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('hosted-authoring-format-example/quiz@2')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Player keeps non-Editor actions', (
    WidgetTester tester,
  ) async {
    final HostedAuthoringContractApi contractApi = _contractApi(editor: false);
    addTearDown(contractApi.close);

    await tester.pumpWidget(_subject(contractApi: contractApi));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('hosted-authoring-open-projects')),
      findsNothing,
    );
    expect(find.byKey(const Key('non-editor-actions')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
