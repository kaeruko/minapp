import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/girls/girls_scaffold.dart';

void main() {
  Future<void> showShell(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    EdgeInsets insets = const EdgeInsets.only(top: 44, bottom: 34),
    double textScale = 1,
    String? title = 'グループ',
    VoidCallback? onAction,
    Decoration? pageBackgroundDecoration,
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
            title: title,
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
            pageBackgroundDecoration: pageBackgroundDecoration,
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

  testWidgets('page background decoration covers title and body', (
    WidgetTester tester,
  ) async {
    const String asset = 'assets/girls/backgrounds/group_home_background.jpg';
    await showShell(
      tester,
      pageBackgroundDecoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage(asset),
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
      ),
    );

    final DecoratedBox background = tester.widget<DecoratedBox>(
      find.byKey(const Key('girls-page-background')),
    );
    final BoxDecoration decoration = background.decoration as BoxDecoration;
    final DecorationImage image = decoration.image!;
    expect((image.image as AssetImage).assetName, asset);
    expect(find.text('グループ'), findsOneWidget);
    expect(find.byKey(const Key('scrolling-content')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses full-width transparent art and moves the title below it',
      (WidgetTester tester) async {
    await showShell(tester);
    final Finder headerFinder = find.byKey(const Key('girls-common-header'));
    final Rect header = tester.getRect(headerFinder);
    final Finder backgroundFinder =
        find.byKey(const Key('girls-header-background'));
    final Rect background = tester.getRect(backgroundFinder);
    final Image backgroundImage = tester.widget<Image>(backgroundFinder);

    expect(
      (backgroundImage.image as AssetImage).assetName,
      'assets/girls/backgrounds/girls_header_bg_top.png',
    );
    expect(header.left, 0);
    expect(header.width, 390);
    expect(background.left, 0);
    expect(background.width, 390);
    expect(header.height, inInclusiveRange(140, 170));
    expect(
      find.descendant(of: headerFinder, matching: find.text('グループ')),
      findsNothing,
    );
    expect(
      tester.getTopLeft(find.text('グループ').first).dy,
      greaterThanOrEqualTo(header.bottom),
    );
    expect(tester.takeException(), isNull);
  });

  for (final double width in <double>[320, 360, 390, 430]) {
    testWidgets('one safe header row at width $width with large text',
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
      final Rect leadingTray =
          tester.getRect(find.byKey(const Key('girls-header-leading-tray')));
      final Rect actionsTray =
          tester.getRect(find.byKey(const Key('girls-header-actions-tray')));
      final Rect logo =
          tester.getRect(find.byKey(const Key('girls-header-logo')));
      final Rect background =
          tester.getRect(find.byKey(const Key('girls-header-background')));
      final Rect footer =
          tester.getRect(find.byKey(const Key('footer-content')));
      expect(action.top, greaterThanOrEqualTo(44));
      expect(leading.top, greaterThanOrEqualTo(44));
      expect(logo.top, greaterThanOrEqualTo(44));
      expect(logo.center.dy, closeTo(leading.center.dy, .5));
      expect(logo.center.dy, closeTo(action.center.dy, .5));
      expect(logo.left, greaterThanOrEqualTo(leadingTray.right));
      expect(logo.right, lessThanOrEqualTo(actionsTray.left));
      expect(header.width, width);
      expect(background.left, 0);
      expect(background.width, width);
      expect(header.height, lessThanOrEqualTo(170));
      expect(footer.bottom, lessThanOrEqualTo(844 - 34));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a deeper notch keeps the entire header row below the inset',
      (WidgetTester tester) async {
    await showShell(
      tester,
      insets: const EdgeInsets.only(top: 59, bottom: 34),
      title: null,
    );
    final Rect header =
        tester.getRect(find.byKey(const Key('girls-common-header')));
    for (final String key in <String>[
      'header-leading',
      'header-action',
      'girls-header-logo',
    ]) {
      final Rect control = tester.getRect(find.byKey(Key(key)));
      expect(control.top, greaterThanOrEqualTo(59));
      expect(control.bottom, lessThan(header.bottom));
    }
    expect(header.height, lessThanOrEqualTo(185));
    expect(find.text('グループ'), findsNothing);
    expect(tester.takeException(), isNull);
  });

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
    final Rect background =
        tester.getRect(find.byKey(const Key('girls-header-background')));
    expect(leading.left, greaterThanOrEqualTo(44));
    expect(action.right, lessThanOrEqualTo(844 - 44));
    expect(background.left, 0);
    expect(background.width, 844);
    expect(body.height, greaterThan(60));
    expect(tester.takeException(), isNull);
  });
}
