import 'package:flutter/material.dart';

@immutable
class BuiltInApp {
  const BuiltInApp({
    required this.id,
    required this.title,
    required this.assetPath,
    required this.searchableText,
    required this.icon,
    required this.cardColor,
    required this.iconBackgroundColor,
    required this.iconBorderColor,
    required this.iconColor,
  });

  final String id;
  final String title;
  final String assetPath;
  final String searchableText;
  final IconData icon;
  final Color cardColor;
  final Color iconBackgroundColor;
  final Color iconBorderColor;
  final Color iconColor;

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
    searchableText:
        'ごしゅじんどこわん ご主人 しばちゃん ここわん なでなで 柴犬 かくれんぼ ゲーム みんアプ公式 サンプル',
    icon: Icons.favorite_rounded,
    cardColor: Color(0xFFFFF7ED),
    iconBackgroundColor: Color(0xFFFED7AA),
    iconBorderColor: Color(0xFFFB923C),
    iconColor: Color(0xFFC2410C),
  ),
  BuiltInApp(
    id: 'novel-starter',
    title: 'ひみつの放課後',
    assetPath: 'assets/builtin/novel_starter/index.html',
    searchableText:
        'ひみつの放課後 ノベルゲーム 女子向け 恋愛 男子 白髪 イケメン レン 小説 ストーリー 選択肢 キャラクター 顔 イラスト AI 改造 スターター みんアプ公式 サンプル',
    icon: Icons.auto_stories_rounded,
    cardColor: Color(0xFFF5F3FF),
    iconBackgroundColor: Color(0xFFE9D5FF),
    iconBorderColor: Color(0xFFA78BFA),
    iconColor: Color(0xFF6D28D9),
  ),
];

List<BuiltInApp> filterBuiltInApps(String query) {
  return builtInApps
      .where((BuiltInApp app) => app.matches(query))
      .toList(growable: false);
}
