import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minapp_mobile/builtin_apps.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('built-in app registry has unique valid entries', () {
    expect(builtInApps, hasLength(8));
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
      builtInApps.singleWhere((BuiltInApp app) => app.id == 'novel-starter').title,
      'ひみつの放課後',
    );
    expect(
      builtInApps.singleWhere((BuiltInApp app) => app.id == 'sing-along').title,
      'うたってみよう',
    );
    expect(
      builtInApps.singleWhere((BuiltInApp app) => app.id == 'minappchi').title,
      'みんあぷっち',
    );
    expect(
      builtInApps.singleWhere((BuiltInApp app) => app.id == 'memo').title,
      'マイメモ帳',
    );
  });

  test('built-in app search filters every registered local app', () {
    expect(filterBuiltInApps(''), hasLength(builtInApps.length));
    expect(filterBuiltInApps('しばちゃん'), hasLength(2));
    expect(filterBuiltInApps('どんぐり').single.id, 'shiba-game');
    expect(filterBuiltInApps('なでなで').single.id, 'shiba-goshujin');

    final Set<String> sideScrollerIds = filterBuiltInApps('横スクロール')
        .map((BuiltInApp app) => app.id)
        .toSet();
    expect(sideScrollerIds, <String>{'shopping-town', 'ol-home'});

    expect(filterBuiltInApps('奥さん').single.id, 'shopping-town');
    expect(filterBuiltInApps('マンション').single.id, 'ol-home');
    expect(filterBuiltInApps('ノベルゲーム').single.id, 'novel-starter');
    expect(filterBuiltInApps('カラオケ').single.id, 'sing-along');
    expect(filterBuiltInApps('みんアプっち').single.id, 'minappchi');
    expect(filterBuiltInApps('メモ帳').single.id, 'memo');
  });

  test('every registered built-in app asset is bundled', () async {
    for (final BuiltInApp app in builtInApps) {
      final String html = await rootBundle.loadString(app.assetPath);
      expect(html, startsWith('<!doctype html>'));
      expect(html, contains('<title>${app.title}</title>'));
    }
  });

  test('memo pad provides fail-fast autosave controls', () async {
    final BuiltInApp memo = builtInApps.singleWhere(
      (BuiltInApp app) => app.id == 'memo',
    );
    final String html = await rootBundle.loadString(memo.assetPath);

    expect(html, contains("const STORAGE_KEY = 'minapp_memo_pad_v1'"));
    expect(html, contains("memo.addEventListener('input', saveMemo)"));
    expect(html, contains("window.confirm('メモをぜんぶ消す？')"));
    expect(html, contains("throw new Error('memo textarea was not found')"));
  });

  test('karaoke uses louder BGM and preserves microphone diagnostics', () async {
    final BuiltInApp karaoke = builtInApps.singleWhere(
      (BuiltInApp app) => app.id == 'sing-along',
    );
    final String html = await rootBundle.loadString(karaoke.assetPath);

    expect(html, contains('const BGM_MASTER_GAIN = 3.0;'));
    expect(html, contains('gainValue * BGM_MASTER_GAIN'));
    expect(html, contains('async function openMicrophone()'));
    expect(html, contains('元のエラー: ${error.name}: ${error.message}'));
  });

  test('novel starter bundles required runtime files', () async {
    expect(
      await rootBundle.loadString('assets/builtin/novel_starter/player.js'),
      contains('MinAppNovelFormat'),
    );
    expect(
      await rootBundle.loadString('assets/builtin/novel_starter/story-validator.js'),
      contains("const FORMAT = 'minapp/novel@1'"),
    );
    final ByteData face =
        await rootBundle.load('assets/builtin/novel_starter/face.jpg');
    expect(face.lengthInBytes, greaterThan(0));
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
