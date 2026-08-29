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
  });

  test('built-in app search filters every registered app', () {
    expect(filterBuiltInApps(''), hasLength(4));
    expect(filterBuiltInApps('しばちゃん'), hasLength(2));
    expect(
      filterBuiltInApps('どんぐり').single.id,
      'shiba-game',
    );
    expect(
      filterBuiltInApps('なでなで').single.id,
      'shiba-goshujin',
    );
    expect(
      filterBuiltInApps('横スクロール').single.id,
      'shopping-town',
    );
    expect(
      filterBuiltInApps('奥さん').single.id,
      'shopping-town',
    );
    expect(
      filterBuiltInApps('ノベルゲーム').single.id,
      'novel-starter',
    );
    expect(
      filterBuiltInApps('女子向け').single.id,
      'novel-starter',
    );
    expect(
      filterBuiltInApps('男子').single.id,
      'novel-starter',
    );
    expect(
      filterBuiltInApps('イラスト').single.id,
      'novel-starter',
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

  test('novel starter documents AI edit points and optional Hosted save', () async {
    final BuiltInApp novel = builtInApps.singleWhere(
      (BuiltInApp app) => app.id == 'novel-starter',
    );
    final String html = await rootBundle.loadString(novel.assetPath);

    expect(html, contains('AIで改造するなら'));
    expect(html, contains('aria-label="白髪の男子キャラクター"'));
    expect(html, contains('<img src="face.jpg" alt="レンの顔">'));
    expect(html, contains("speaker: 'レン'"));
    expect(html, contains("const SAVE_KEY = 'novel_progress';"));
    expect(html, contains('window.minapp.state.get(SAVE_KEY)'));
    expect(html, contains('window.minapp.state.set(SAVE_KEY'));
    expect(html, contains('window.minapp.state.delete(SAVE_KEY)'));
    expect(html, contains('この環境はセーブなし'));

    final ByteData portrait = await rootBundle.load(
      'assets/builtin/novel_starter/face.jpg',
    );
    expect(portrait.lengthInBytes, greaterThan(0));
  });
}
