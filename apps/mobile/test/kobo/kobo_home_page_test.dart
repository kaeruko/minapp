import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/kobo/kobo_app.dart';
import 'package:minapp_mobile/kobo/kobo_components.dart';
import 'package:minapp_mobile/kobo/kobo_home_page.dart';
import 'package:minapp_mobile/kobo/kobo_models.dart';

Future<void> _pumpKobo(
  WidgetTester tester, {
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const KoboApp());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Kobo home shows Phase 1 content', (WidgetTester tester) async {
    await _pumpKobo(tester, size: const Size(390, 844));

    expect(find.byType(KoboHomePage), findsOneWidget);
    expect(find.text('みんアプ工房'), findsOneWidget);
    expect(find.text('今日、なに作る？'), findsOneWidget);
    expect(find.text('新しいアプリをつくる'), findsOneWidget);
    expect(find.byKey(const Key('kobo-hero-sign')), findsOneWidget);
    expect(find.byType(KoboCategoryCard), findsNWidgets(4));
    expect(find.text('晩酌予算'), findsOneWidget);
    expect(find.text('町中華メモ'), findsNWidgets(2));
    expect(find.text('昼めしルーレット'), findsOneWidget);
    expect(find.text('小遣い管理'), findsOneWidget);
    expect(
      find.byKey(const Key('kobo-category-image-晩酌予算')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('kobo-category-image-町中華メモ')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('kobo-category-image-昼めしルーレット')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('kobo-category-image-小遣い管理')),
      findsOneWidget,
    );
    expect(find.text('俺のアプリ'), findsOneWidget);
  });

  testWidgets('featured example cards forward taps to the host', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    KoboCategory? tapped;
    await tester.pumpWidget(MaterialApp(
      home: KoboHomePage(onCategorySelected: (KoboCategory category) {
        tapped = category;
      }),
    ));
    await tester.pumpAndSettle();

    const List<String> titles = <String>[
      '晩酌予算',
      '町中華メモ',
      '昼めしルーレット',
      '小遣い管理',
    ];
    for (final String title in titles) {
      final Finder button = find.byKey(Key('kobo-category-$title'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(tapped?.title, title);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Kobo home has no overflow around the reference width', (
    WidgetTester tester,
  ) async {
    await _pumpKobo(tester, size: const Size(390, 700));

    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byKey(const Key('kobo-home-scroll')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Kobo home has no overflow on a small screen', (
    WidgetTester tester,
  ) async {
    await _pumpKobo(tester, size: const Size(320, 568));

    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byKey(const Key('kobo-home-scroll')),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('unfinished actions stay in Kobo and explain their status', (
    WidgetTester tester,
  ) async {
    await _pumpKobo(tester, size: const Size(390, 844));

    await tester.tap(find.byKey(const Key('kobo-create-cta')));
    await tester.pump();

    expect(find.text('アプリ作成機能は次のPhaseで利用できるようになります'), findsOneWidget);
    expect(find.text('みんアプ工房'), findsOneWidget);

    await tester.tap(find.byKey(const Key('kobo-nav-community')));
    await tester.pump();

    expect(find.text('みんなのアプリは次のPhaseで利用できるようになります'), findsOneWidget);
    expect(find.text('みんアプ工房'), findsOneWidget);
  });
}
