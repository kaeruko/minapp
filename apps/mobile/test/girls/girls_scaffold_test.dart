import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/girls/girls_scaffold.dart';

void main() {
  Future<void> showShell(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    EdgeInsets insets = const EdgeInsets.only(top: 44, bottom: 34),
    double textScale = 1,
    VoidCallback? onAction,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            padding: insets,
            textScaler: TextScaler.linear(textScale),
          ),
          child: GirlsScaffold(
            title: 'グループ',
            leading: IconButton(
              key: const Key('header-leading'),
              onPressed: () {},
              icon: const Icon(Icons.arrow_back),
            ),
            actions: <Widget>[
              IconButton(
                key: const Key('header-action'),
                onPressed: onAction ?? () {},
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.settings),
              ),
            ],
            body: ListView.builder(
              key: const Key('scrolling-content'),
              itemExtent: 80,
              itemCount: 50,
              itemBuilder: (BuildContext context, int index) =>
                  Text('Item $index'),
            ),
            bottomNavigationBar: const SizedBox(
              key: Key('footer-content'),
              height: 82,
              child: Center(child: Icon(Icons.home)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('art stays fixed while the page scrolls and actions remain live',
      (WidgetTester tester) async {
    int taps = 0;
    await showShell(tester, onAction: () => taps++);
    final Rect backgroundBefore =
        tester.getRect(find.byKey(const Key('girls-body-background')));
    final Rect headerBefore =
        tester.getRect(find.byKey(const Key('girls-common-header')));
    final double trackedBefore = tester.getTopLeft(find.text('Item 2')).dy;

    expect(find.byKey(const Key('girls-header-leading-tray')), findsOneWidget);
    expect(find.byKey(const Key('girls-header-actions-tray')), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('scrolling-content')),
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byKey(const Key('girls-body-background'))),
      backgroundBefore,
    );
    expect(
      tester.getRect(find.byKey(const Key('girls-common-header'))),
      headerBefore,
    );
    expect(tester.getTopLeft(find.text('Item 2')).dy, lessThan(trackedBefore));
    await tester.tap(find.byKey(const Key('header-action')));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  for (final double width in <double>[320, 360, 390, 430]) {
    testWidgets('safe controls and no overflow at width $width with large text',
        (WidgetTester tester) async {
      await showShell(
        tester,
        size: Size(width, 844),
        textScale: 2,
      );
      final Rect header =
          tester.getRect(find.byKey(const Key('girls-common-header')));
      final Rect action =
          tester.getRect(find.byKey(const Key('header-action')));
      final Rect leading =
          tester.getRect(find.byKey(const Key('header-leading')));
      final Rect footer =
          tester.getRect(find.byKey(const Key('footer-content')));
      expect(action.top, greaterThanOrEqualTo(44));
      expect(leading.top, greaterThanOrEqualTo(44));
      expect(header.height, lessThan(300));
      expect(footer.bottom, lessThanOrEqualTo(844 - 34));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'landscape keeps controls out of side insets and leaves body space',
      (WidgetTester tester) async {
    await showShell(
      tester,
      size: const Size(844, 390),
      insets: const EdgeInsets.fromLTRB(44, 0, 44, 21),
      textScale: 2,
    );
    final Rect leading =
        tester.getRect(find.byKey(const Key('header-leading')));
    final Rect action = tester.getRect(find.byKey(const Key('header-action')));
    final Rect body =
        tester.getRect(find.byKey(const Key('scrolling-content')));
    expect(leading.left, greaterThanOrEqualTo(44));
    expect(action.right, lessThanOrEqualTo(844 - 44));
    expect(body.height, greaterThan(60));
    expect(tester.takeException(), isNull);
  });
}
