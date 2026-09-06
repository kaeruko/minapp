import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/api.dart';
import 'package:minapp_mobile/girls/girls_app_management_api.dart';
import 'package:minapp_mobile/girls/girls_app_test_actions.dart';
import 'package:minapp_mobile/girls/hosted_girls_api.dart';

const String _groupId = '22222222222222222222222222222222';
const String _appId = '44444444444444444444444444444444';

HostedGirlsApi _api() => HostedGirlsApi(
      baseUri: Uri.parse('https://hosted.example.test'),
      client: MockClient((http.Request request) async {
        fail('Unexpected HTTP request while rendering action buttons: ${request.url}');
      }),
    );

ManagedGirlsAppDetail _detail(String builtinId) {
  final HostedGroupApp app = HostedGroupApp(
    appId: _appId,
    groupId: _groupId,
    title: builtinId == 'novel-editor' ? 'ノベルエディタ' : 'ノベルプレイヤー',
    sourceKind: 'builtin',
    createdAt: DateTime.utc(2026, 9, 6, 9),
    publishedVersion: null,
    builtinId: builtinId,
    builtinAssetPath: builtinId == 'novel-editor'
        ? 'assets/builtin/novel_editor/index.html'
        : 'assets/builtin/novel_starter/index.html',
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
      sourceUpdatedAt: DateTime.utc(2026, 9, 6, 9),
      publishedAt: null,
      groupName: 'ノベル制作部',
    ),
    sourceHistory: const <GirlsSourceHistoryItem>[],
    publishedHistory: const <GirlsPublishedHistoryItem>[],
  );
}

const AuthenticatedSession _session = AuthenticatedSession(
  accessToken: 'owner-token',
  expiresIn: 3600,
);

void main() {
  testWidgets('installed novel-editor exposes the Novel project action', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GirlsAppTestActions(
            api: _api(),
            session: _session,
            detail: _detail('novel-editor'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('girls-novel-open-projects')), findsOneWidget);
    expect(find.text('ノベル作品を編集'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Novel Player does not receive Authoring UI', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GirlsAppTestActions(
            api: _api(),
            session: _session,
            detail: _detail('novel-starter'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('girls-novel-open-projects')), findsNothing);
    expect(find.text('ノベル作品を編集'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
