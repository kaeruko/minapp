import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const List<String> assets = <String>[
    'assets/girls/mascot_pair.svg',
    'assets/girls/mascot_white.svg',
    'assets/girls/mascot_black.svg',
  ];

  for (final String asset in assets) {
    testWidgets('Girls mascot SVG loads: $asset', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SvgPicture.asset(asset)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(SvgPicture), findsOneWidget);
    });
  }
}
