import 'package:flutter/material.dart';

import 'kobo_assets.dart';

@immutable
class KoboCategory {
  const KoboCategory({required this.title, required this.assetPath});

  final String title;
  final String assetPath;
}

@immutable
class KoboAppSummary {
  const KoboAppSummary({
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;
}

@immutable
class KoboHomeData {
  const KoboHomeData({required this.categories, required this.apps});

  final List<KoboCategory> categories;
  final List<KoboAppSummary> apps;

  static const KoboHomeData phaseOne = KoboHomeData(
    categories: <KoboCategory>[
      KoboCategory(title: '晩酌予算', assetPath: KoboAssets.drinkIzakaya),
      KoboCategory(title: '町中華メモ', assetPath: KoboAssets.gourmet),
      KoboCategory(title: '昼めしルーレット', assetPath: KoboAssets.games),
      KoboCategory(title: '小遣い管理', assetPath: KoboAssets.allowance),
    ],
    apps: <KoboAppSummary>[
      KoboAppSummary(
        title: 'せんべろ計算機',
        description: '今月あと何回飲みに行ける？',
        icon: Icons.calculate_outlined,
      ),
      KoboAppSummary(
        title: '町中華メモ',
        description: 'また行きたい店を記録',
        icon: Icons.edit_note_outlined,
      ),
    ],
  );
}
