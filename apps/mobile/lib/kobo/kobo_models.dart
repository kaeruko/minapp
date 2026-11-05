import 'package:flutter/material.dart';

import 'kobo_assets.dart';

@immutable
class KoboCategory {
  const KoboCategory({required this.title, required this.assetPath});

  final String title;
  final String assetPath;
}

@immutable
class KoboHomeData {
  const KoboHomeData({required this.categories});

  final List<KoboCategory> categories;

  static const KoboHomeData phaseOne = KoboHomeData(
    categories: <KoboCategory>[
      KoboCategory(title: '晩酌予算', assetPath: KoboAssets.drinkIzakaya),
      KoboCategory(title: '町中華メモ', assetPath: KoboAssets.gourmet),
      KoboCategory(title: '昼めしルーレット', assetPath: KoboAssets.games),
      KoboCategory(title: '小遣い管理', assetPath: KoboAssets.allowance),
    ],
  );
}
