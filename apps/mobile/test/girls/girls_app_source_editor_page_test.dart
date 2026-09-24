import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minapp_mobile/girls/api.dart';
import 'package:minapp_mobile/girls/girls_app_management_api.dart';
import 'package:minapp_mobile/girls/girls_app_source_editor_page.dart';
import 'package:minapp_mobile/girls/girls_current_group_store.dart';
import 'package:minapp_mobile/girls/girls_home_shop_shell.dart';
import 'package:minapp_mobile/girls/girls_source_zip.dart';
import 'package:minapp_mobile/girls/hosted_girls_api.dart';

const String _groupId = '0123456789abcdef0123456789abcdef';
const String _appId = 'abcdef0123456789abcdef0123456789';

class _EmptyGroupStore implements GirlsCurrentGroupStore {
  @override
  Future<String?> load() async => null;

  @override
  Future<void> save(String groupId) async {}

  @override
  Future<void> clear() async {}
}

void main() {
  testWidgets('source editor inside Girls shell keeps its input connection',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 823);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    final archive = GirlsSourceArchive.fromEntries(<String, Uint8List>{
      'index.html': Uint8List.fromList(utf8.encode('<html>original</html>')),
    });
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      if (request.url.path.endsWith('/source')) {
        return http.Response.bytes(archive.encode(), 200, headers: {
          'content-type': 'application/zip',
          'x-minapp-source-revision': '1',
          'x-minapp-source-sha256': '0' * 64,
        });
      }
      return http.Response(
          request.url.path == '/hosted/groups'
              ? '{"groups": []}'
              : '{"apps": []}',
          200,
          headers: {'content-type': 'application/json'});
    });
    addTearDown(client.close);
    await tester.pumpWidget(MaterialApp(
      home: GirlsHomeShopShell(
        api: HostedGirlsApi(
            baseUri: Uri.parse('https://example.com'), client: client),
        session: const AuthenticatedSession(
            accessToken: 'test-token', expiresIn: 3600),
        onLogout: () {},
        currentGroupStore: _EmptyGroupStore(),
      ),
    ));
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(find.descendant(
      of: find.byType(GirlsHomeShopShell),
      matching: find.byType(Navigator),
    ));
    navigator.push<int>(MaterialPageRoute(
        builder: (_) => GirlsAppSourceEditorPage(
              api: GirlsAppManagementApi(
                  baseUri: Uri.parse('https://example.com'), client: client),
              accessToken: 'test-token',
              groupId: _groupId,
              appId: _appId,
              title: 'うさぎのおやつやさん',
              expectedRevision: 1,
            )));
    await tester.pumpAndSettle();
    expect(
      find.text('編集版を編集中。保存しても公開版は変わりません。'),
      findsOneWidget,
    );
    expect(find.textContaining('revision'), findsNothing);
    expect(find.text('編集版を保存'), findsOneWidget);
    final codeField = find.byKey(const Key('girls-source-editor-code'));
    await tester.tap(codeField);
    await tester.pump();
    final editableState =
        tester.state<EditableTextState>(find.byType(EditableText));
    final focusNode = editableState.widget.focusNode;
    expect(focusNode.hasFocus, isTrue);
    tester.testTextInput.log.clear();
    for (final bottom in <double>[1, 80, 180, 300]) {
      tester.view.viewInsets = FakeViewPadding(bottom: bottom);
      await tester.pump();
      expect(tester.state<EditableTextState>(find.byType(EditableText)),
          same(editableState));
      expect(focusNode.hasFocus, isTrue);
    }
    await tester.pumpAndSettle();
    expect(
        tester.testTextInput.log
            .where((call) => call.method == 'TextInput.hide'),
        isEmpty);
    expect(tester.getSize(codeField).height, greaterThan(80));
    tester.testTextInput.enterText('<html>editing works</html>');
    await tester.pump();
    expect(editableState.widget.controller.text, '<html>editing works</html>');
    final editingValue = TextEditingValue(
      text: '<html>にほんご</html>',
      selection: const TextSelection.collapsed(offset: 10),
      composing: const TextRange(start: 6, end: 10),
    );
    tester.testTextInput.updateEditingValue(editingValue);
    await tester.pump();
    for (final bottom in <double>[180, 1, 0, 1, 180, 300, 0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: bottom);
      await tester.pump();
      expect(tester.state<EditableTextState>(find.byType(EditableText)),
          same(editableState));
      expect(focusNode.hasFocus, isTrue);
      expect(editableState.widget.controller.value, editingValue);
    }
    await tester.pumpAndSettle();
    expect(
        tester.testTextInput.log.where((call) =>
            call.method == 'TextInput.hide' ||
            call.method == 'TextInput.clearClient'),
        isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'keyboard-visible source editor keeps a usable code viewport',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(411, 823));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final GirlsSourceArchive archive = GirlsSourceArchive.fromEntries(
        <String, Uint8List>{
          'index.html': Uint8List.fromList(
            utf8.encode(
              '<!doctype html><style>body { min-height: 100%; }</style>',
            ),
          ),
        },
      );
      final GirlsAppManagementApi api = GirlsAppManagementApi(
        baseUri: Uri.parse('https://example.com'),
        client: MockClient((http.Request request) async {
          expect(request.method, 'GET');
          expect(
            request.url.path,
            '/hosted/groups/$_groupId/apps/$_appId/source',
          );
          return http.Response.bytes(
            archive.encode(),
            200,
            headers: <String, String>{
              'content-type': 'application/zip',
              'x-minapp-source-revision': '1',
              'x-minapp-source-sha256': '0' * 64,
            },
          );
        }),
      );
      addTearDown(api.close);

      final ValueNotifier<EdgeInsets> viewInsets =
          ValueNotifier<EdgeInsets>(EdgeInsets.zero);
      addTearDown(viewInsets.dispose);

      await tester.pumpWidget(
        MaterialApp(
          builder: (BuildContext context, Widget? child) {
            return ValueListenableBuilder<EdgeInsets>(
              valueListenable: viewInsets,
              builder: (
                BuildContext context,
                EdgeInsets currentInsets,
                Widget? ignored,
              ) {
                final MediaQueryData media = MediaQuery.of(context);
                return MediaQuery(
                  data: media.copyWith(viewInsets: currentInsets),
                  child: child!,
                );
              },
            );
          },
          home: GirlsAppSourceEditorPage(
            api: api,
            accessToken: 'test-token',
            groupId: _groupId,
            appId: _appId,
            title: 'みんあぷっち',
            expectedRevision: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Finder codeField = find.byKey(
        const Key('girls-source-editor-code'),
      );
      expect(codeField, findsOneWidget);
      expect(
        find.byKey(const Key('girls-source-editor-file-menu')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('girls-source-editor-help')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('girls-source-editor-help')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('girls-source-editor-help-dialog')),
        findsOneWidget,
      );
      expect(find.text('コード編集で迷ったら？'), findsOneWidget);
      expect(
        find.text('わからないところは、AIに相談しながら進めて大丈夫だよ。'),
        findsOneWidget,
      );
      expect(find.text('使い方ガイドを見る'), findsOneWidget);
      await tester.tap(find.byKey(const Key('girls-source-editor-help-close')));
      await tester.pumpAndSettle();

      await tester.tap(codeField);
      await tester.pump();

      final EditableText beforeResize = tester.widget<EditableText>(
        find.byType(EditableText),
      );
      final FocusNode focusNode = beforeResize.focusNode;
      final EditableTextState inputState =
          tester.state<EditableTextState>(find.byType(EditableText));
      expect(focusNode.hasFocus, isTrue);

      viewInsets.value = const EdgeInsets.only(bottom: 300);
      await tester.pumpAndSettle();

      final EditableText afterResize = tester.widget<EditableText>(
        find.byType(EditableText),
      );
      expect(identical(afterResize.focusNode, focusNode), isTrue);
      expect(tester.state<EditableTextState>(find.byType(EditableText)),
          same(inputState));
      expect(afterResize.focusNode.hasFocus, isTrue);
      expect(tester.getSize(codeField).height, greaterThan(80));
      expect(tester.takeException(), isNull);
    },
  );
}
