import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/builtin_apps.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('built-in app registry has unique valid entries', () {
    expect(builtInApps, hasLength(2));
    expect(
      builtInApps.map((BuiltInApp app) => app.id).toSet(),
      hasLength(builtInApps.length),
    );
    expect(
      builtInApps.map((BuiltInApp app) => app.assetPath).toSet(),
      hasLength(builtInApps.length),
    );

    final RegExp validAssetPath = RegExp(
      r'^assets/builtin/[a-z0-9_-]+/index\.html$',
    );
    for (final BuiltInApp app in builtInApps) {
      expect(app.id, isNotEmpty);
      expect(app.title, isNotEmpty);
      expect(app.searchableText, contains(app.title));
      expect(app.assetPath, matches(validAssetPath));
    }
  });

  test('built-in app search filters every registered app', () {
    expect(filterBuiltInApps(''), hasLength(2));
    expect(filterBuiltInApps('しばちゃん'), hasLength(2));
    expect(
      filterBuiltInApps('どんぐり').single.id,
      'shiba-game',
    );
    expect(
      filterBuiltInApps('なでなで').single.id,
      'shiba-goshujin',
    );
    expect(filterBuiltInApps('じかんわり'), isEmpty);
  });

  test('every registered built-in app asset is bundled', () async {
    for (final BuiltInApp app in builtInApps) {
      final String html = await rootBundle.loadString(app.assetPath);
      expect(html, startsWith('<!doctype html>'));
      expect(html, contains('<title>${app.title}</title>'));
    }
  });
}
