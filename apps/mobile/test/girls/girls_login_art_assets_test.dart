import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Girls PNG login art assets render', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              Image(
                image: AssetImage(
                  'assets/girls/generated/bg_pastel_pattern.png',
                ),
                width: 360,
                height: 220,
                fit: BoxFit.cover,
              ),
              Image(
                image: AssetImage(
                  'assets/girls/generated/border_lace_heart.png',
                ),
                width: 360,
                fit: BoxFit.fitWidth,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
