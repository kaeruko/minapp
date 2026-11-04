import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/kobo/kobo_app.dart';
import 'package:minapp_mobile/kobo/kobo_components.dart';
import 'package:minapp_mobile/kobo/kobo_home_page.dart';

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
    expect(find.text('AIで作ってもらう'), findsOneWidget);
    expect(find.byType(KoboCategoryCard), findsNWidgets(4));
    expect(find.text('晩酌予算'), findsOneWidget);
    expect(find.text('町中華メモ'), findsNWidgets(2));
    expect(find.text('昼メシルーレット'), findsOneWidget);
    expect(find.text('小遣い管理'), findsOneWidget);
    expect(find.text('俺のアプリ'), findsOneWidget);
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

    expect(find.text('AIで作る機能は次のPhaseで利用できるようになります'), findsOneWidget);
    expect(find.text('みんアプ工房'), findsOneWidget);

    await tester.tap(find.byKey(const Key('kobo-nav-community')));
    await tester.pump();

    expect(find.text('みんなのアプリは次のPhaseで利用できるようになります'), findsOneWidget);
    expect(find.text('みんアプ工房'), findsOneWidget);
  });
}
