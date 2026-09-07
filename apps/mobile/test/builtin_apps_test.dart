import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/builtin_apps.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('built-in app registry has unique valid entries', () {
    expect(builtInApps, hasLength(4));
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
    expect(
      builtInApps.where((BuiltInApp app) => app.id == 'novel-starter'),
      isEmpty,
    );
  });

  test('built-in app search filters every registered local app', () {
    expect(filterBuiltInApps(''), hasLength(builtInApps.length));
    expect(filterBuiltInApps('しばちゃん'), hasLength(2));
    expect(
      filterBuiltInApps('どんぐり').single.id,
      'shiba-game',
    );
    expect(
      filterBuiltInApps('なでなで').single.id,
      'shiba-goshujin',
    );

    final Set<String> sideScrollerIds = filterBuiltInApps('横スクロール')
        .map((BuiltInApp app) => app.id)
        .toSet();
    expect(sideScrollerIds, <String>{'shopping-town', 'ol-home'});

    expect(
      filterBuiltInApps('奥さん').single.id,
      'shopping-town',
    );
    expect(
      filterBuiltInApps('マンション').single.id,
      'ol-home',
    );
    expect(filterBuiltInApps('ノベルゲーム'), isEmpty);
    expect(filterBuiltInApps('女子向け'), isEmpty);
    expect(filterBuiltInApps('じかんわり'), isEmpty);
  });

  test('every registered built-in app asset is bundled', () async {
    for (final BuiltInApp app in builtInApps) {
      final String html = await rootBundle.loadString(app.assetPath);
      expect(html, startsWith('<!doctype html>'));
      expect(html, contains('<title>${app.title}</title>'));
    }
  });

  test('shopping town exposes touch controls and fail-fast initialization', () async {
    final BuiltInApp shoppingTown = builtInApps.singleWhere(
      (BuiltInApp app) => app.id == 'shopping-town',
    );
    final String html = await rootBundle.loadString(shoppingTown.assetPath);

    expect(html, contains('id="duckButton"'));
    expect(html, contains('id="jumpButton"'));
    expect(html, contains('Game initialization failed: required DOM element is missing.'));
    expect(html, contains('requestAnimationFrame(frame)'));
    expect(html, contains('しょうがいぶつを よけて スーパーへ！'));
  });
}
