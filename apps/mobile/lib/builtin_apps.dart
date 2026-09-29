import 'package:flutter/material.dart';

@immutable
class BuiltInApp {
  const BuiltInApp({
    required this.id,
    required this.title,
    required this.assetPath,
    required this.topBackgroundColor,
    required this.searchableText,
    required this.icon,
    required this.cardColor,
    required this.iconBackgroundColor,
    required this.iconBorderColor,
    required this.iconColor,
    this.accepts = const <String>[],
    this.edits = const <String>[],
  });

  final String id;
  final String title;
  final String assetPath;
  /// Matches the bundled app's background at the top of its viewport.
  final Color topBackgroundColor;
  final String searchableText;
  final IconData icon;
  final Color cardColor;
  final Color iconBackgroundColor;
  final Color iconBorderColor;
  final Color iconColor;
  final List<String> accepts;
  final List<String> edits;

  bool get isPlayer => accepts.isNotEmpty;
  bool get isEditor => edits.isNotEmpty;
  bool get isStandalone => accepts.isEmpty && edits.isEmpty;

  String get catalogKey => 'builtin-$id';

  bool matches(String query) {
    final String normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return true;
    return searchableText.toLowerCase().contains(normalizedQuery);
  }
}

const List<BuiltInApp> builtInApps = <BuiltInApp>[
  BuiltInApp(
    id: 'shiba-game',
    title: 'しば犬どんぐりキャッチ',
    assetPath: 'assets/builtin/shiba_donguri/index.html',
    topBackgroundColor: Color(0xFFBDE8FF),
    searchableText:
        'しば犬どんぐりキャッチ 柴犬 しばちゃん どんぐり ゲーム みんアプ公式 サンプル',
    icon: Icons.pets_rounded,
    cardColor: Color(0xFFFFFBEB),
    iconBackgroundColor: Color(0xFFFDE68A),
    iconBorderColor: Color(0xFFF59E0B),
    iconColor: Color(0xFF92400E),
  ),
  BuiltInApp(
    id: 'shiba-goshujin',
    title: 'ごしゅじんどこわん',
    assetPath: 'assets/builtin/shiba_goshujin/index.html',
    topBackgroundColor: Color(0xFFBCE8FF),
    searchableText:
        'ごしゅじんどこわん ご主人 しばちゃん ここわん なでなで 柴犬 かくれんぼ ゲーム みんアプ公式 サンプル',
    icon: Icons.favorite_rounded,
    cardColor: Color(0xFFFFF7ED),
    iconBackgroundColor: Color(0xFFFED7AA),
    iconBorderColor: Color(0xFFFB923C),
    iconColor: Color(0xFFC2410C),
  ),
  BuiltInApp(
    id: 'shopping-town',
    title: 'おかいもの いくわよ',
    assetPath: 'assets/builtin/shopping_town/index.html',
    topBackgroundColor: Color(0xFFBFE9FF),
    searchableText:
        'おかいもの いくわよ お買い物 奥さん 横スクロール ランナー ジャンプ しゃがむ 町 スーパー ゲーム みんアプ公式 サンプル',
    icon: Icons.shopping_bag_rounded,
    cardColor: Color(0xFFFFF7ED),
    iconBackgroundColor: Color(0xFFFED7AA),
    iconBorderColor: Color(0xFFFB923C),
    iconColor: Color(0xFFC2410C),
  ),
  BuiltInApp(
    id: 'ol-home',
    title: 'OLさん おうちにかえる',
    assetPath: 'assets/builtin/ol_home/index.html',
    topBackgroundColor: Color(0xFF24345D),
    searchableText:
        'OLさん おうちにかえる 帰宅 会社員 マンション 窓 明かり 4つ 同じ色 近道 横スクロール ゲーム みんアプ公式 サンプル',
    icon: Icons.apartment_rounded,
    cardColor: Color(0xFFF5F3FF),
    iconBackgroundColor: Color(0xFFE0E7FF),
    iconBorderColor: Color(0xFF818CF8),
    iconColor: Color(0xFF4338CA),
  ),
  BuiltInApp(
    id: 'novel-starter',
    title: 'ひみつの放課後',
    assetPath: 'assets/builtin/novel_starter/index.html',
    topBackgroundColor: Color(0xFF7770AE),
    searchableText:
        'ひみつの放課後 パステルノベル ノベルゲーム 物語 選択肢 恋愛 Girls 女子向け みんアプ公式 サンプル',
    icon: Icons.auto_stories_rounded,
    cardColor: Color(0xFFF5EEFF),
    iconBackgroundColor: Color(0xFFE9D5FF),
    iconBorderColor: Color(0xFFC4B5FD),
    iconColor: Color(0xFF6D4AA5),
    accepts: <String>['minapp/novel@1'],
  ),
  BuiltInApp(
    id: 'sing-along',
    title: 'うたってみよう',
    assetPath: 'assets/builtin/sing_along/index.html',
    topBackgroundColor: Color(0xFFFFE7F2),
    searchableText:
        'うたってみよう カラオケ 歌 うた 録音 BGM マイク 音楽 Girls 女子向け みんアプ公式 サンプル',
    icon: Icons.mic_rounded,
    cardColor: Color(0xFFFFF1E8),
    iconBackgroundColor: Color(0xFFFFD9C2),
    iconBorderColor: Color(0xFFFFA66B),
    iconColor: Color(0xFFB45309),
  ),
  BuiltInApp(
    id: 'minappchi',
    title: 'みんあぷっち',
    assetPath: 'assets/builtin/minappchi/index.html',
    topBackgroundColor: Color(0xFFFFE8F2),
    searchableText:
        'みんあぷっち みんアプっち 育成 ペット たまご お世話 おやつ Girls 女子向け みんアプ公式 サンプル',
    icon: Icons.pets_rounded,
    cardColor: Color(0xFFFFEEF0),
    iconBackgroundColor: Color(0xFFFFCDD2),
    iconBorderColor: Color(0xFFFF8A94),
    iconColor: Color(0xFFA73548),
  ),
  BuiltInApp(
    id: 'memo',
    title: 'マイメモ帳',
    assetPath: 'assets/builtin/memo_pad/index.html',
    topBackgroundColor: Color(0xFFFFFAF7),
    searchableText:
        'マイメモ帳 メモ メモ帳 ノート 自動保存 Girls 女子向け みんアプ公式',
    icon: Icons.edit_note_rounded,
    cardColor: Color(0xFFF0FBFF),
    iconBackgroundColor: Color(0xFFD9F4FF),
    iconBorderColor: Color(0xFF91D5ED),
    iconColor: Color(0xFF477E94),
  ),
];

List<BuiltInApp> filterBuiltInApps(String query) {
  return builtInApps
      .where((BuiltInApp app) => app.matches(query))
      .toList(growable: false);
}
