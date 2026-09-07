import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/api.dart';
import 'package:minapp_mobile/girls/girls_app_management_api.dart';
import 'package:minapp_mobile/girls/girls_app_test_actions.dart';
import 'package:minapp_mobile/girls/hosted_girls_api.dart';
import 'package:minapp_mobile/hosted_authoring_contract_api.dart';

const String _groupId = '22222222222222222222222222222222';
const String _appId = '44444444444444444444444444444444';

HostedGirlsApi _api() => HostedGirlsApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: MockClient((http.Request request) async {
        fail('Unexpected HostedGirlsApi request while rendering actions: ${request.url}');
      }),
    );

ManagedGirlsAppDetail _detail({required String title}) {
  final HostedGroupApp app = HostedGroupApp(
    appId: _appId,
    groupId: _groupId,
    title: title,
    sourceKind: 'uploaded',
    createdAt: DateTime.utc(2026, 9, 7, 3),
    publishedVersion: null,
  );
  return ManagedGirlsAppDetail(
    summary: ManagedGirlsApp(
      app: app,
      stats: const GirlsAppStats(
        totalPlays: 0,
        uniqueUsers: 0,
        monthlyPlays: 0,
      ),
      visibility: 'visible',
      sourceRevision: 1,
      sourceUpdatedAt: DateTime.utc(2026, 9, 7, 3),
      publishedAt: null,
      groupName: '制作部',
    ),
    sourceHistory: const <GirlsSourceHistoryItem>[],
    publishedHistory: const <GirlsPublishedHistoryItem>[],
  );
}

HostedAuthoringContractApi _contractApi({required bool editor}) {
  return HostedAuthoringContractApi(
    baseUri: Uri.parse('https://hosted.example.test'),
    client: MockClient((http.Request request) async {
      expect(
        request.url.path,
        '/hosted/authoring/groups/$_groupId/apps',
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'apps': <Object?>[
            <String, Object?>{
              'app_id': _appId,
              'group_id': _groupId,
              'title': editor ? 'Quiz Editor' : 'Quiz Player',
              'edits': editor ? <String>['example/quiz@1'] : <String>[],
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

const AuthenticatedSession _session = AuthenticatedSession(
  accessToken: 'owner-token',
  expiresIn: 3600,
);

void main() {
  testWidgets('third-party Editor exposes generic project action', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final HostedAuthoringContractApi contractApi = _contractApi(editor: true);
    addTearDown(contractApi.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GirlsAppTestActions(
            api: _api(),
            session: _session,
            detail: _detail(title: 'Third-party Quiz Editor'),
            authoringContractApi: contractApi,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('girls-authoring-open-projects')), findsOneWidget);
    expect(find.text('作品を編集'), findsOneWidget);
    expect(find.byKey(const Key('girls-app-try-published')), findsNothing);
    expect(find.byKey(const Key('girls-app-preview-latest')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Player keeps runtime test actions and no Authoring action', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final HostedAuthoringContractApi contractApi = _contractApi(editor: false);
    addTearDown(contractApi.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GirlsAppTestActions(
            api: _api(),
            session: _session,
            detail: _detail(title: 'Third-party Quiz Player'),
            authoringContractApi: contractApi,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('girls-authoring-open-projects')), findsNothing);
    expect(find.byKey(const Key('girls-app-try-published')), findsOneWidget);
    expect(find.byKey(const Key('girls-app-preview-latest')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
