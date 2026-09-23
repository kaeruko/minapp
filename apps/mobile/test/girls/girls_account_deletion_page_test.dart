import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/api.dart';
import 'package:minapp_mobile/girls/girls_account_deletion_page.dart';
import 'package:minapp_mobile/girls/girls_current_group_store.dart';
import 'package:minapp_mobile/girls/hosted_girls_api.dart';

const String _ownerGroupId = '11111111111111111111111111111111';
const String _memberGroupId = '22222222222222222222222222222222';

class _MemoryCurrentGroupStore implements GirlsCurrentGroupStore {
  String? value = _ownerGroupId;
  bool cleared = false;

  @override
  Future<String?> load() async => value;

  @override
  Future<void> save(String groupId) async {
    value = groupId;
  }

  @override
  Future<void> clear() async {
    cleared = true;
    value = null;
  }
}

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: const <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    );

void main() {
  testWidgets(
    'confirmed deletion removes owned groups, then account, and returns success',
    (WidgetTester tester) async {
      final List<String> requests = <String>[];
      final _MemoryCurrentGroupStore store = _MemoryCurrentGroupStore();
      final HostedGirlsApi api = HostedGirlsApi(
        baseUri: Uri.parse('https://example.com'),
        client: MockClient((http.Request request) async {
          requests.add('${request.method} ${request.url.path}');
          expect(request.headers['authorization'], 'Bearer test-token');
          if (request.method == 'GET' &&
              request.url.path == '/hosted/groups') {
            return _json(<String, Object?>{
              'groups': <Object?>[
                <String, Object?>{
                  'group_id': _ownerGroupId,
                  'name': '自分のグループ',
                  'role': 'owner',
                  'status': 'active',
                },
                <String, Object?>{
                  'group_id': _memberGroupId,
                  'name': '参加中のグループ',
                  'role': 'member',
                  'status': 'active',
                },
              ],
            });
          }
          if (request.method == 'DELETE' &&
              request.url.path == '/hosted/groups/$_ownerGroupId') {
            return http.Response('', 204);
          }
          if (request.method == 'DELETE' &&
              request.url.path == '/hosted/account') {
            return http.Response('', 204);
          }
          fail('Unexpected request: ${request.method} ${request.url.path}');
        }),
      );
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: FilledButton(
                  key: const Key('open-delete-page'),
                  onPressed: () async {
                    result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (BuildContext context) =>
                            GirlsAccountDeletionPage(
                          api: api,
                          session: const AuthenticatedSession(
                            accessToken: 'test-token',
                            expiresIn: 3600,
                          ),
                          currentGroupStore: store,
                        ),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open-delete-page')));
      await tester.pumpAndSettle();
      expect(find.text('アカウントを完全に削除'), findsOneWidget);

      await tester.tap(find.byKey(const Key('girls-account-delete-start')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('girls-account-delete-confirm-dialog')),
        findsOneWidget,
      );
      expect(find.text('アカウントを削除しますか？'), findsOneWidget);

      await tester.tap(find.byKey(const Key('girls-account-delete-confirm')));
      await tester.pumpAndSettle();

      expect(
        requests,
        <String>[
          'GET /hosted/groups',
          'DELETE /hosted/groups/$_ownerGroupId',
          'DELETE /hosted/account',
        ],
      );
      expect(store.cleared, isTrue);
      expect(result, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
