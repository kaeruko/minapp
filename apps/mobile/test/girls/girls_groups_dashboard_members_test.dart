import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/api.dart';
import 'package:minapp_mobile/girls/girls_current_group_store.dart';
import 'package:minapp_mobile/girls/girls_groups_dashboard_page.dart';
import 'package:minapp_mobile/girls/hosted_girls_api.dart';

const HostedGroup _group = HostedGroup(
  groupId: '0123456789abcdef0123456789abcdef',
  name: 'みんなのアトリエ',
  role: 'owner',
  status: 'active',
);

class _MemoryGroupStore implements GirlsCurrentGroupStore {
  String? value = _group.groupId;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<String?> load() async => value;

  @override
  Future<void> save(String groupId) async => value = groupId;
}

String _userId(int value) => value.toRadixString(16).padLeft(32, '0');

Map<String, Object?> _member(
  int id,
  String loginId, {
  bool owner = false,
  String? displayName,
}) {
  return <String, Object?>{
    'user_id': _userId(id),
    'login_id': loginId,
    'role': owner ? 'owner' : 'member',
    'status': 'active',
    if (displayName != null) 'display_name': displayName,
  };
}

HostedGirlsApi _fakeApi(
  List<Map<String, Object?>> members, {
  List<Map<String, Object?>> apps = const <Map<String, Object?>>[],
}) {
  return HostedGirlsApi(
    baseUri: Uri.parse('https://example.com'),
    client: MockClient((http.Request request) async {
      final String path = request.url.path;
      late final Map<String, Object?> payload;
      if (request.method == 'GET' && path == '/hosted/groups') {
        payload = <String, Object?>{
          'groups': <Object?>[
            <String, Object?>{
              'group_id': _group.groupId,
              'name': _group.name,
              'role': _group.role,
              'status': _group.status,
            },
          ],
        };
      } else if (request.method == 'GET' &&
          path == '/hosted/groups/${_group.groupId}/members') {
        payload = <String, Object?>{'members': members};
      } else if (request.method == 'GET' &&
          path == '/hosted/groups/${_group.groupId}/apps') {
        payload = <String, Object?>{'apps': apps};
      } else {
        fail('Unexpected request: ${request.method} ${request.url}');
      }
      return http.Response(
        jsonEncode(payload),
        200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );
    }),
  );
}

Future<void> _pumpDashboard(
  WidgetTester tester,
  List<Map<String, Object?>> members, {
  List<Map<String, Object?>> apps = const <Map<String, Object?>>[],
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: GirlsGroupsDashboardPage(
        api: _fakeApi(members, apps: apps),
        session: const AuthenticatedSession(
          accessToken: 'test-token',
          expiresIn: 3600,
        ),
        currentGroup: _group,
        onCurrentGroupChanged: (_) {},
        currentGroupStore: _MemoryGroupStore(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('latest app card is tappable', (WidgetTester tester) async {
    const String appId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    await _pumpDashboard(
      tester,
      <Map<String, Object?>>[
        _member(1, 'review', owner: true),
      ],
      apps: <Map<String, Object?>>[
        <String, Object?>{
          'app_id': appId,
          'group_id': _group.groupId,
          'title': 'うさぎのおやつやさん',
          'source_kind': 'zip',
          'created_at': '2026-09-18T00:00:00Z',
          'published_version': 1,
          'owner_user_id': _userId(1),
          'editable': false,
          'source_revision': null,
        },
      ],
    );

    final Finder latest = find.byKey(
      const ValueKey<String>('girls-latest-app-$appId'),
    );
    expect(latest, findsOneWidget);
    final InkWell inkWell = tester.widget<InkWell>(latest);
    expect(inkWell.onTap, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows every member inline when the group has four or fewer', (
    WidgetTester tester,
  ) async {
    await _pumpDashboard(tester, <Map<String, Object?>>[
      _member(1, 'review', owner: true),
      _member(2, 'alice'),
      _member(3, 'bob'),
      _member(4, 'carol'),
    ]);

    expect(find.byKey(const Key('girls-current-group-members')), findsOneWidget);
    expect(find.text('4人'), findsOneWidget);
    expect(find.text('review'), findsOneWidget);
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('bob'), findsOneWidget);
    expect(find.text('carol'), findsOneWidget);
    expect(
      find.byKey(const Key('girls-current-group-members-all')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('prefers display name and falls back to login ID', (
    WidgetTester tester,
  ) async {
    await _pumpDashboard(tester, <Map<String, Object?>>[
      _member(1, 'review', owner: true, displayName: 'ねんね'),
      _member(2, 'alice'),
    ]);

    expect(find.text('ねんね'), findsOneWidget);
    expect(find.text('review'), findsNothing);
    expect(find.text('alice'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows four members inline and opens the full list for larger groups', (
    WidgetTester tester,
  ) async {
    await _pumpDashboard(tester, <Map<String, Object?>>[
      _member(1, 'review', owner: true),
      _member(2, 'alice'),
      _member(3, 'bob'),
      _member(4, 'carol'),
      _member(5, 'diana'),
      _member(6, 'erika'),
    ]);

    expect(find.text('6人'), findsOneWidget);
    expect(find.text('review'), findsOneWidget);
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('bob'), findsOneWidget);
    expect(find.text('carol'), findsOneWidget);
    expect(find.text('diana'), findsNothing);
    expect(find.text('erika'), findsNothing);
    expect(find.text('あと2人・全員を見る'), findsOneWidget);

    final Finder showAll =
        find.byKey(const Key('girls-current-group-members-all'));
    await tester.ensureVisible(showAll);
    await tester.pumpAndSettle();
    await tester.tap(showAll);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('girls-all-members-sheet')), findsOneWidget);
    expect(find.text('メンバー 6人'), findsOneWidget);
    expect(find.text('diana'), findsOneWidget);
    expect(find.text('erika'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
